//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IOrderCallbackReceiver } from "../../../../interfaces/GMX/IOrderCallbackReceiver.sol";
import { IGasFeeCallbackReceiver } from "gmx-synthetics/callback/IGasFeeCallbackReceiver.sol";
import { AddressProvider } from "../../../../core/config/AddressProvider.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EventUtils } from "gmx-synthetics/event/EventUtils.sol";
import { ProtocolStorage } from "../../../../core/ProtocolStorage.sol";
import { MarketNeutralStorage } from "../../storage/MarketNeutralStorage.sol";
import { MarketNeutralLib } from "../../../../lib/MarketNeutral/MarketNeutralLib.sol";
import { IWETH } from "../../../../interfaces/IWETH.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolLib } from "../../../../lib/Protocol.lib.sol";
import { Roles } from "../../../../security/Roles.sol";
import { ProxyManager } from "../../storage/ProxyManager.sol";
import { MarketNeutralProxy } from "../proxy.sol";
import { GMXMarketsRegistry } from "../../../../core/config/gmxMarkets.sol";
import { GMXPrices } from "../../../../periphery/utilsGMX/GMXPrices.sol";

contract ClosePositionCallbacks is IOrderCallbackReceiver, IGasFeeCallbackReceiver, ReentrancyGuard {
    
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    AddressProvider public immutable addressProvider;
    address public immutable usdc;
    address public immutable weth;
    GMXMarketsRegistry public immutable gmxMarkets;
    
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        weth = addressProvider.getAddress("WETH");
        usdc = addressProvider.getAddress("USDC");
        gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
    }

    modifier onlyOrderHandler() {
        require(msg.sender == addressProvider.getAddress("OrderHandlerGMX"), "Only order handler");
        _;
    }

    event IsLongSideCalculationFailed(
        bytes32 indexed orderKey,
        uint256 indexed positionId
    );

    event PositionSideClosedSuccess(
        address indexed receiver,
        uint256 indexed positionId,
        bool isLongSide,
        address outputToken,
        uint256 outputAmount
        
    );

    event ExecutionProcessingFailed(
        bytes32 indexed orderKey,
        uint256 indexed positionId,
        address indexed receiver,
        string reason
    );

    event EmergencyWithdraw(
        address indexed admin,
        address indexed token,
        address indexed to,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    event PositionRescued(
        address indexed user,
        uint256 indexed positionId,
        bool isLongSide,
        address outputToken,
        uint256 outputAmount,
        bool rescued
    );

    function afterOrderExecution(
        bytes32 key,
        EventUtils.EventLogData memory orderData,
        EventUtils.EventLogData memory eventData
    ) external override onlyOrderHandler nonReentrant { // discutir si puedo quitar el cntrolador...
        
        (, address orderMarket) = orderData.addressItems.getWithoutRevert("market");
        (, address outputToken) = eventData.addressItems.getWithoutRevert("outputToken");
        (, uint256 outputAmount) = eventData.uintItems.getWithoutRevert("outputAmount");
        
        uint256 collateralTokenPrice = outputToken == usdc ? 1
            : GMXPrices(addressProvider.getAddress("GMXPrices")).getPrice(gmxMarkets.getMarket("ETHUSDC"));

        MarketNeutralStorage marketNeutralStorage = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage"));

        MarketNeutralLib.PendingOrder memory pendingOrder = marketNeutralStorage.getPendingOrder(key);

        uint256 executionPrice;
        try GMXPrices(addressProvider.getAddress("GMXPrices")).getPrice(orderMarket) returns (uint256 price) {
            executionPrice = price;
        } catch {
            executionPrice = 1;
        }

        MarketNeutralLib.RawExecutionData memory executionData = MarketNeutralLib.RawExecutionData({
            positionId: pendingOrder.positionId,  
            receiver: pendingOrder.receiver,       
            outputToken: outputToken,            
            outputAmount: outputAmount, 
            pnl: 0,                      
            executionPrice: executionPrice,        
            collateralTokenPrice: collateralTokenPrice, 
            isLongSide: false, 
            processed: false,
            timestamp: block.timestamp
        });
        
        marketNeutralStorage.storeRawExecutionData(key, executionData); // seguro que hay datos que no necesitamos
        
        bool isLongSideCalculated = false;
        
        try this.calculateIsLongSide(pendingOrder.receiver, pendingOrder.positionId, orderMarket) returns (bool isLong) {
            MarketNeutralLib.RawExecutionData memory data = marketNeutralStorage.getRawExecutionData(key);
            data.isLongSide = isLong;
            marketNeutralStorage.storeRawExecutionData(key, data);
            isLongSideCalculated = true;
        } catch {
            emit IsLongSideCalculationFailed(key, pendingOrder.positionId);
        }
        
        uint256 proxyId = MarketNeutralProxy(pendingOrder.proxy).getId();
        
        try this.processAndTransfer(key, address(marketNeutralStorage)) {
            marketNeutralStorage.updateExecutionProcessed(key, true);
            marketNeutralStorage.removeUserPendingOrderKey(pendingOrder.receiver, key);
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(proxyId);

            emit PositionSideClosedSuccess(
                pendingOrder.receiver,
                pendingOrder.positionId,
                isLongSideCalculated,
                outputToken,
                outputAmount
            );
        } catch Error(string memory reason) {
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, reason);
        } catch {
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, "Unknown error");
        }
    }

    /**
     * @notice Checks if the closed order is long or short
     * @dev Separated function to use try-catch
     */
    function calculateIsLongSide(
        address receiver,
        uint256 positionId,
        address orderMarket
    ) external view returns (bool) {
        require(msg.sender == address(this), "Internal only");
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));  // se puede optimizar a solo una llamada
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(receiver, positionId); // se puede optimizar a solo una llamada
        address marketLong = abi.decode(position.positionData[2], (address));
        return (orderMarket == marketLong);
    }

    /**
     * @notice Processes the data and transfers funds.
     * @dev external to allow try-catch, only called internally via this.
     */
    function processAndTransfer(bytes32 key, address _marketNeutralStorage) external {
        require(msg.sender == address(this), "Internal only");
        MarketNeutralLib.RawExecutionData memory data = MarketNeutralStorage(_marketNeutralStorage).getRawExecutionData(key);
        require(data.positionId != 0, "No data for this key");
        require(!data.processed, "Already processed");
        
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(data.receiver, data.positionId); // se puede optimizar a solo una llamada

        uint256 tokenDecimals = data.outputToken == usdc ? 6 : 18;
        uint256 outputUsdValue = (data.outputAmount * data.collateralTokenPrice) / (10 ** tokenDecimals);
        
        if (data.isLongSide) {
            position.positionData[12] = abi.encode(data.executionPrice);
        } else {
            position.positionData[13] = abi.encode(data.executionPrice);
        }
        
        uint256 currentFinalUsdValue = abi.decode(position.positionData[11], (uint256));
        uint256 totalFinalUsdValue = currentFinalUsdValue + outputUsdValue;
        position.positionData[11] = abi.encode(totalFinalUsdValue);

        int256 currentPnl = abi.decode(position.positionData[14], (int256));
        uint256 initialUsdValueHalf = abi.decode(position.positionData[8], (uint256)) / 2;
        uint256 totalFinalUsdValueScaled = totalFinalUsdValue * 10**tokenDecimals;
        int256 totalPnl = currentPnl - (int256(initialUsdValueHalf) - int256(totalFinalUsdValueScaled));
        position.positionData[14] = abi.encode(totalPnl);
        position.pnl = totalPnl;
        
        uint256 finalPriceTokenLong = abi.decode(position.positionData[12], (uint256));
        uint256 finalPriceTokenShort = abi.decode(position.positionData[13], (uint256));
        bool bothSidesClosed = (finalPriceTokenLong != 0 && finalPriceTokenShort != 0);
        
        if (bothSidesClosed) {
            position.positionData[10] = abi.encode(block.timestamp);
            position.isActive = false;
            _protocolStorage.decreaseGlobalPositionActivePositions(data.receiver);
        }
        
        _protocolStorage.updateUserFullPosition(data.receiver, data.positionId, position); // aqui probablemente se pueda optimizar
        
        MarketNeutralStorage(_marketNeutralStorage).updatePendingOrder(
            key, 
            MarketNeutralLib.PendingOrder(data.receiver, address(0), data.positionId, false) // aqui probablemente se pueda optimizar
        );
        
        if (data.outputAmount > 0) {
            if (data.outputToken == weth) {
                IWETH(weth).withdraw(data.outputAmount);
                (bool success, ) = data.receiver.call{value: data.outputAmount}("");
                require(success, "ETH transfer failed");
            } else {
                // aqui if(performance fee isActivated) transfer performance fee to fee manager contract
                // o llamada view a fee manager contract para obtener instrucciones de envios.
                IERC20(data.outputToken).safeTransfer(data.receiver, data.outputAmount);
            }
        }
    }

    // AÑADIR FUNCIONES PARA POST CANCELLATION O FRONZEN
    function afterOrderCancellation(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}
    function afterOrderFrozen(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}

    function refundExecutionFee(bytes32 key, EventUtils.EventLogData memory /* eventData */) external payable {
        MarketNeutralLib.PendingOrder memory pendingOrder = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).getPendingOrder(key);
        if (msg.value > 0 && pendingOrder.receiver != address(0)) {
            (bool success, ) = pendingOrder.receiver.call{value: msg.value}("");
            require(success, "Refund execution fee transfer failed");
        }
    }   

    /**
     * @notice Función de rescue SIMPLE para cuando el callback falla
     * @dev Solo necesita el orderKey - Los datos ya están guardados on-chain
     * @param key El key de la orden que falló (del evento ExecutionProcessingFailed)
     */
    function rescuePosition(bytes32 key) external nonReentrant {
        address marketNeutralStorage = addressProvider.getAddress("MarketNeutralStorage");
        MarketNeutralLib.RawExecutionData memory data = MarketNeutralStorage(marketNeutralStorage).getRawExecutionData(key);
        MarketNeutralLib.PendingOrder memory pendingOrder = MarketNeutralStorage(marketNeutralStorage).getPendingOrder(key);
        
        require(data.positionId != 0, "No data for this key");
        require(data.receiver == msg.sender, "Not your position");
        require(!data.processed, "Already processed");
        
        try this.processAndTransfer(key, marketNeutralStorage) {
            MarketNeutralStorage(marketNeutralStorage).updateExecutionProcessed(key, true);
            MarketNeutralStorage(marketNeutralStorage).removeUserPendingOrderKey(msg.sender, key);
            uint256 proxyId = MarketNeutralProxy(pendingOrder.proxy).getId();
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(proxyId);
            emit PositionRescued(
                msg.sender,
                data.positionId,
                data.isLongSide,
                data.outputToken,
                data.outputAmount,
                true
            );
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Rescue failed: ", reason)));
        }
    }
    
    // ===== FUNCIONES DE EMERGENCIA PARA EL EQUIPO =====
    
    /**
     * @notice Retiro de emergencia de tokens (solo para casos extremos del 1%)
     * @dev Solo puede ser llamado por un admin autorizado con rol PROTOCOL_ADMIN
     * @dev Se usa cuando rescuePosition falla y necesitamos devolver fondos manualmente
     * @param token Dirección del token a retirar (WETH, USDC, etc)
     * @param to Dirección destino (normalmente el usuario afectado)
     * @param amount Cantidad a retirar
     * @param reason Razón del retiro de emergencia (para auditoría)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount,
        string calldata reason
    ) external nonReentrant {
        // Solo admins del protocolo pueden llamar esta función
        require(Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender), "Not authorized");
        require(to != address(0), "Invalid destination");
        require(amount > 0, "Amount must be > 0");
        require(bytes(reason).length > 0, "Reason required");
        
        if (token == address(0)) {
            // Retirar ETH nativo
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Retirar token ERC20
            IERC20(token).safeTransfer(to, amount);
        }
        
        emit EmergencyWithdraw(msg.sender, token, to, amount, reason, block.timestamp);
    }
    
    /**
     * @notice Retiro de emergencia de ETH (envuelto como WETH)
     * @dev Wrapper para emergencyWithdraw específico para WETH/ETH
     * @param to Dirección destino
     * @param amount Cantidad en wei
     * @param unwrap Si true, unwrap WETH → ETH antes de enviar
     * @param reason Razón del retiro
     */
    function emergencyWithdrawETH(
        address to,
        uint256 amount,
        bool unwrap,
        string calldata reason
    ) external nonReentrant {
        require(Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender) , "Not authorized");
        require(to != address(0), "Invalid destination");
        require(amount > 0, "Amount must be > 0");
                
        if (unwrap) {
            // Unwrap WETH → ETH y enviar
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
            
            emit EmergencyWithdraw(msg.sender, address(0), to, amount, reason, block.timestamp);
        } else {
            // Enviar WETH directamente
            IERC20(weth).safeTransfer(to, amount);
            
            emit EmergencyWithdraw(msg.sender, weth, to, amount, reason, block.timestamp);
        }
    }

}