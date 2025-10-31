//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IOrderCallbackReceiver } from "../../../../interfaces/GMX/IOrderCallbackReceiver.sol";
import { AddressProvider } from "../../../../core/config/AddressProvider.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EventUtils } from "../../../../lib/GMX lib/EventUtils.sol";
import { ProtocolStorage } from "../../../../core/ProtocolStorage.sol";
import { MarketNeutralStorage } from "../../storage/MarketNeutralStorage.sol";
import { MarketNeutralLib } from "../../../../lib/MarketNeutral/MarketNeutralLib.sol";
import { IWETH } from "../../../../interfaces/IWETH.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolLib } from "../../../../lib/Protocol.lib.sol";
import { Roles } from "../../../../security/Roles.sol";
import { ProxyManager } from "../../storage/ProxyManager.sol";
import { MarketNeutralProxy } from "../proxy.sol";

contract ClosePositionCallbacks is IOrderCallbackReceiver, ReentrancyGuard {
    
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
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
        uint256 outputAmount,
        int256 pnl
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
    ) external override onlyOrderHandler {
        
        (, address orderMarket) = orderData.addressItems.getWithoutRevert("market");
        (, address outputToken) = eventData.addressItems.getWithoutRevert("outputToken");
        (, uint256 outputAmount) = eventData.uintItems.getWithoutRevert("outputAmount");
        (, int256 basePnlUsd) = eventData.intItems.getWithoutRevert("basePnlUsd");
        (, uint256 executionPrice) = eventData.uintItems.getWithoutRevert("executionPrice");
        (, uint256 collateralTokenPriceMin) = eventData.uintItems.getWithoutRevert("collateralTokenPrice.min");
        (, uint256 collateralTokenPriceMax) = eventData.uintItems.getWithoutRevert("collateralTokenPrice.max");
        uint256 collateralTokenPrice = (collateralTokenPriceMin + collateralTokenPriceMax) / 2;
        // Cache MarketNeutralStorage for pending orders
        MarketNeutralStorage marketNeutralStorage = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage"));
        // Obtener la orden pendiente (mínima operación de storage)
        MarketNeutralLib.PendingOrder memory pendingOrder = marketNeutralStorage.getPendingOrder(key);
        
        // ⚠️ GUARDAR DATOS INMEDIATAMENTE - ANTES de cualquier otra operación
        // Esto minimiza el riesgo de fallo antes de guardar
        MarketNeutralLib.RawExecutionData memory executionData = MarketNeutralLib.RawExecutionData({
            positionId: pendingOrder.positionId,  // Viene de la orden
            receiver: pendingOrder.receiver,       // Viene de la orden
            outputToken: outputToken,              // De GMX
            outputAmount: outputAmount,            // De GMX
            pnl: basePnlUsd,                      // De GMX
            executionPrice: executionPrice,        // De GMX
            collateralTokenPrice: collateralTokenPrice, // De GMX
            isLongSide: false,  // ⚠️ TEMPORAL - Se actualiza después si es necesario
            processed: false,
            timestamp: block.timestamp
        });
        
        MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).storeRawExecutionData(key, executionData);
        
        // ===== FASE 1.5: Determinar qué pata es (puede fallar, pero datos ya guardados) =====
        // Si esto falla, al menos tenemos los datos básicos para emergency withdraw
        bool isLongSideCalculated = false;
        
        try this.calculateIsLongSide(pendingOrder.receiver, pendingOrder.positionId, orderMarket) returns (bool isLong) {
            // Actualizar el campo isLongSide con el valor correcto
            MarketNeutralStorage storageContract = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage"));
            MarketNeutralLib.RawExecutionData memory data = storageContract.getRawExecutionData(key);
            data.isLongSide = isLong;
            storageContract.storeRawExecutionData(key, data);
            isLongSideCalculated = true;
        } catch {
            // Si falla calcular isLongSide, dejamos false
            // El emergency withdraw manual puede corregirlo
            emit IsLongSideCalculationFailed(key, pendingOrder.positionId);
        }
        
        // ===== FASE 2: PROCESAR Y TRANSFERIR (puede fallar, pero datos ya guardados) =====
        
        try this.processAndTransfer(key) {
            // Éxito → marcar como procesado
            MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).updateExecutionProcessed(key, true);
            
            // Eliminar key del array de pending orders del usuario
            marketNeutralStorage.removeUserPendingOrderKey(pendingOrder.receiver, key);
            uint256 proxyId = MarketNeutralProxy(pendingOrder.proxy).getId();
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(proxyId);

            emit PositionSideClosedSuccess(
                pendingOrder.receiver,
                pendingOrder.positionId,
                isLongSideCalculated,
                outputToken,
                outputAmount,
                basePnlUsd
            );
        } catch Error(string memory reason) {
            // Falló el procesamiento, pero datos guardados para rescue
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, reason);
        } catch {
            // Falló sin mensaje
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, "Unknown error");
        }
    }

    /**
     * @notice Calcula si la orden que se cerró es Long o Short
     * @dev Función separada para poder usar try-catch
     */
    function calculateIsLongSide(
        address receiver,
        uint256 positionId,
        address orderMarket
    ) external view returns (bool) {
        require(msg.sender == address(this), "Internal only");
        
        // Cache ProtocolStorage to avoid multiple getAddress calls
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        ProtocolLib.User memory user = _protocolStorage.getUser(receiver);
        (ProtocolLib.Position memory position, ) = _protocolStorage.getUserPosition(
            user.globalPosition.positions, 
            positionId
        );
        
        address marketLong = abi.decode(position.positionData[2], (address));
        return (orderMarket == marketLong);
    }

    /**
     * @notice Procesa los datos y transfiere fondos (función interna pesada)
     * @dev Solo puede ser llamada por afterOrderExecution o rescuePosition
     */
    function processAndTransfer(bytes32 key) external {
        require(msg.sender == address(this) || msg.sender == addressProvider.getAddress("OrderHandlerGMX"), "Internal only");
        
        MarketNeutralLib.RawExecutionData memory data = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).getRawExecutionData(key);
        require(data.positionId != 0, "No data for this key");
        require(!data.processed, "Already processed");
        
        // Cache addresses to avoid multiple getAddress calls
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address usdc = addressProvider.getAddress("USDC");
        address weth = addressProvider.getAddress("WETH");
        // Obtener el usuario y su posición
        ProtocolLib.User memory user = _protocolStorage.getUser(data.receiver);
        (ProtocolLib.Position memory position, uint256 positionIndex) = _protocolStorage.getUserPosition(
            user.globalPosition.positions, 
            data.positionId
        );
        
        // Calcular valor en USD
        uint256 tokenDecimals = data.outputToken == usdc ? 6 : 18;
        uint256 outputUsdValue = (data.outputAmount * data.collateralTokenPrice) / (10 ** tokenDecimals);
        
        // Actualizar el precio final correspondiente
        if (data.isLongSide) {
            position.positionData[12] = abi.encode(data.executionPrice);
        } else {
            position.positionData[13] = abi.encode(data.executionPrice);
        }
        
        // Acumular PNL
        int256 currentPnl = abi.decode(position.positionData[14], (int256));
        int256 totalPnl = currentPnl + data.pnl;
        position.positionData[14] = abi.encode(totalPnl);
        position.pnl = totalPnl;
        
        // Acumular valor final USD
        uint256 currentFinalUsdValue = abi.decode(position.positionData[11], (uint256));
        uint256 totalFinalUsdValue = currentFinalUsdValue + outputUsdValue;
        position.positionData[11] = abi.encode(totalFinalUsdValue);
        
        // Verificar si ambas patas están cerradas
        uint256 finalPriceTokenLong = abi.decode(position.positionData[12], (uint256));
        uint256 finalPriceTokenShort = abi.decode(position.positionData[13], (uint256));
        bool bothSidesClosed = (finalPriceTokenLong != 0 && finalPriceTokenShort != 0);
        
        if (bothSidesClosed) {
            position.positionData[10] = abi.encode(block.timestamp);
            user.globalPosition.activePositions -= 1;
        }
        
        // Actualizar storage
        user.globalPosition.positions[positionIndex] = position;
        _protocolStorage.updateUserGlobalPosition(data.receiver, user.globalPosition);
        
        MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).updatePendingOrder(
            key, 
            MarketNeutralLib.PendingOrder(data.receiver, address(0), data.positionId, false)
        );
        
        // Transferir fondos al usuario
        if (data.outputAmount > 0) {
            if (data.outputToken == weth) {
                IWETH(weth).withdraw(data.outputAmount);
                (bool success, ) = data.receiver.call{value: data.outputAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(data.outputToken).safeTransfer(data.receiver, data.outputAmount);
            }
        }
    }

    // AÑADIR FUNCIONES PARA POST CANCELLATION O FRONZEN
    function afterOrderCancellation(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}
    function afterOrderFrozen(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}

    receive() external payable {}

    /**
     * @notice Función de rescue SIMPLE para cuando el callback falla
     * @dev Solo necesita el orderKey - Los datos ya están guardados on-chain
     * @param key El key de la orden que falló (del evento ExecutionProcessingFailed)
     */
    function rescuePosition(bytes32 key) external nonReentrant {
        MarketNeutralLib.RawExecutionData memory data = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).getRawExecutionData(key);
        
        require(data.positionId != 0, "No data for this key");
        require(data.receiver == msg.sender, "Not your position");
        require(!data.processed, "Already processed");
        
        // Llamar a processAndTransfer para completar el procesamiento
        try this.processAndTransfer(key) {
            // Marcar como procesado
            MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).updateExecutionProcessed(key, true);
            
            // Eliminar key del array de pending orders del usuario
            MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).removeUserPendingOrderKey(msg.sender, key);
            
            emit PositionRescued(
                msg.sender,
                data.positionId,
                data.isLongSide,
                data.outputToken,
                data.outputAmount,
                true // rescued = true
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
        
        // Cache WETH address to avoid multiple getAddress calls
        address weth = addressProvider.getAddress("WETH");
        
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