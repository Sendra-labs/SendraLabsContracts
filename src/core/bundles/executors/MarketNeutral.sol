//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";
import { DecoderLib } from "../../../lib/Decoder.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { IExchangeRouter } from "../../../interfaces/GMX/IExchangeRouter.sol";
import { IOrderVault } from "../../../interfaces/GMX/IOrderVault.sol";
import { BaseOrderUtils } from "../../../lib/GMX lib/BaseOrdersUtils.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { IOrderCallbackReceiver } from "../../../interfaces/GMX/IOrderCallbackReceiver.sol";
import { EventUtils } from "../../../lib/GMX lib/EventUtils.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";

interface IWETH {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}

contract MarketNeutral is ReentrancyGuard, IOrderCallbackReceiver {
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    AddressProvider public immutable addressProvider;
    
    // Struct para guardar datos crudos de ejecución (SIEMPRE se guarda, incluso si falla el procesamiento)
    struct RawExecutionData {
        uint256 positionId;
        address receiver;
        address outputToken;
        uint256 outputAmount;
        int256 pnl;
        uint256 executionPrice;
        uint256 collateralTokenPrice;
        bool isLongSide;
        bool processed;  // true si ya se procesó exitosamente
        uint256 timestamp;
    }
    
    // Mapping de order key → datos de ejecución
    mapping(bytes32 => RawExecutionData) public rawExecutionData;
    
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    modifier onlyProtocol() {
        if(!Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function execute(uint8 functionId, bytes[] calldata _data) external payable onlyProtocol {
        ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
        if     (functionId == 0) openPositionWithEther(params);
        else if(functionId == 1) closePositionV2(params);
        else if(functionId == 2) openPositionWithUSDC(params);
        else if(functionId == 3) openMarketNeutral(params);
    }

    function openPositionWithEther(ProtocolLib.DeFiParam[] memory _params) public payable nonReentrant {

        uint256 ethAmount = _params[0].x;            
        uint256 sizeDeltaUsd = _params[1].x;         
        uint256 acceptablePrice = _params[2].x;      
        uint256 executionFee = _params[3].x;
        address market = _params[4].w;
        address receiver = _params[5].w;
        bool isLong = _params[6].z;

        uint256 totalEthNeeded = ethAmount + executionFee;
        
        // Cache addresses to avoid multiple getAddress calls
        address weth = addressProvider.getAddress("WETH");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");        
        
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: weth,
                swapPath: new address[](0)
            }),
            numbers: BaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: BaseOrderUtils.OrderType.MarketIncrease,
            decreasePositionSwapType: BaseOrderUtils.DecreasePositionSwapType.NoSwap,
            isLong: isLong,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0),
            dataList: new bytes32[](0)
        });
        
        bytes[] memory multicallData = new bytes[](2);
        
        multicallData[0] = abi.encodeCall(
            IExchangeRouter.sendWnt,
            (orderVault, totalEthNeeded)
        );
        
        multicallData[1] = abi.encodeCall(
            IExchangeRouter.createOrder,
            (orderParams)
        );
        
        IExchangeRouter(addressProvider.getAddress("ExchangeRouterGMX")).multicall{value: msg.value}(multicallData);
        
        emit PositionOpened(receiver, market, weth, ethAmount, sizeDeltaUsd, isLong);
    }

    function openPositionWithUSDC(ProtocolLib.DeFiParam[] memory _params) public payable nonReentrant {

        uint256 usdcAmount = _params[0].x;           // Cantidad de USDC como colateral
        uint256 sizeDeltaUsd = _params[1].x;         // Tamaño de la posición en USD
        uint256 acceptablePrice = _params[2].x;      // Precio aceptable
        uint256 executionFee = _params[3].x;         // Fee de ejecución en ETH
        address market = _params[4].w;               // Dirección del market
        address receiver = _params[5].w;             // Receptor de la posición
        bool isLong = _params[6].z;                  // Long o Short
        
        address _exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        IERC20(usdc).safeIncreaseAllowance(_exchangeRouter, usdcAmount);
        
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: usdc,
                swapPath: new address[](0)
            }),
            numbers: BaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: BaseOrderUtils.OrderType.MarketIncrease,
            decreasePositionSwapType: BaseOrderUtils.DecreasePositionSwapType.NoSwap,
            isLong: isLong,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0),
            dataList: new bytes32[](0)
        });
        
        bytes[] memory multicallData = new bytes[](3);
        
        multicallData[0] = abi.encodeCall(
            IExchangeRouter.sendTokens,
            (usdc, orderVault, usdcAmount)
        );
        
        multicallData[1] = abi.encodeCall(
            IExchangeRouter.sendWnt,
            (orderVault, executionFee)
        );
        
        multicallData[2] = abi.encodeCall(
            IExchangeRouter.createOrder,
            (orderParams)
        );
        
        IExchangeRouter(_exchangeRouter).multicall{value: executionFee}(multicallData);
        
        emit PositionOpened(receiver, market, usdc, usdcAmount, sizeDeltaUsd, isLong);
    }


    function calculateLeverage(uint256 collateralAmount, uint256 sizeDeltaUsd) public pure returns (uint256) {
        if (collateralAmount == 0) return 0;
        
        
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e24; 
        
        return (adjustedSizeDelta * 1e18) / collateralAmount;
    }
  
    function calculateCollateralForLeverage(uint256 sizeDeltaUsd, uint256 leverage) public pure returns (uint256) {
        if (leverage == 0) return 0;
        
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e24;
        
        return (adjustedSizeDelta * 1e18) / leverage;
    }


    function closePositionV2(
        ProtocolLib.DeFiParam[] memory _params
    ) internal {
        // Cache addresses to avoid multiple getAddress calls
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address weth = addressProvider.getAddress("WETH");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        
        uint256 sizeDeltaUsd = _params[0].x;  // ref0001
        uint256 acceptablePrice = _params[1].x;      
        uint256 executionFee = _params[2].x;
        address market = _params[3].w;
        address receiver = _params[4].w;
        bool isLong = _params[5].z; 
        uint256 positionId = _params[6].x;
        
        // Obtener la posición para leer isNativeToken
        ProtocolLib.User memory user = _protocolStorage.getUser(receiver);
        (ProtocolLib.Position memory position, ) = _protocolStorage.getUserPosition(
            user.globalPosition.positions, 
            positionId
        );
        
        // Leer isNativeToken de positionData[1]
        // Si es true → WETH, si es false → USDC
        bool isNativeToken = abi.decode(position.positionData[1], (bool));
        address collateralToken = isNativeToken ? weth : usdc;
        
        // Gas suficiente para el callback (almacenamiento + transferencias)
        // Estimado: ~200k gas para las operaciones en afterOrderExecution
        uint256 callbackGasLimit = 200000;
        
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this), // ✅ Fondos vienen al contrato primero (para seguridad en callbacks)
                cancellationReceiver: receiver, // Si se cancela, van al usuario
                callbackContract: address(this), // thisAddress.afterOrderExecution() para actualizar storage y transferir fondos
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: collateralToken, // ✅ Dinámico: WETH o USDC según isNativeToken
                swapPath: new address[](0)
            }),
            numbers: BaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd, //-
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: callbackGasLimit, // Gas adicional para el callback
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: BaseOrderUtils.OrderType.MarketDecrease,
            decreasePositionSwapType: BaseOrderUtils.DecreasePositionSwapType.NoSwap,
            isLong: isLong,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0),
            dataList: new bytes32[](0)
        });

        IExchangeRouter exchangeRouterInstance = IExchangeRouter(exchangeRouter);

        // Enviar WNT para el execution fee
        exchangeRouterInstance.sendWnt{value: executionFee}(orderVault, executionFee);
        
        // Crear la orden - createOrder retorna el key directamente
        bytes32 key = exchangeRouterInstance.createOrder(orderParams);

        _protocolStorage.updatePendingOrder(key, ProtocolLib.PendingOrder(receiver, positionId, true));
        
        // Agregar key al array de pending orders del usuario (para rescue en frontend)
        _protocolStorage.addUserPendingOrderKey(receiver, key);

        emit PositionClosed(receiver, market, sizeDeltaUsd, isLong); 
    }

    function afterOrderExecution(
        bytes32 key,
        EventUtils.EventLogData memory orderData,
        EventUtils.EventLogData memory eventData
    ) external override {
        require(msg.sender == addressProvider.getAddress("OrderHandlerGMX"), "Only order handler");
        
        // ===== FASE 1: EXTRAER Y GUARDAR DATOS CRUDOS PRIMERO (MÁXIMA PRIORIDAD) =====
        // ⚠️ CRÍTICO: Guardar datos ANTES de cualquier operación compleja
        // Si falla después, al menos tenemos los datos para rescue manual
        
        // Extraer datos directamente de GMX (estas operaciones son muy simples)
        (, address orderMarket) = orderData.addressItems.getWithoutRevert("market");
        (, address outputToken) = eventData.addressItems.getWithoutRevert("outputToken");
        (, uint256 outputAmount) = eventData.uintItems.getWithoutRevert("outputAmount");
        (, int256 basePnlUsd) = eventData.intItems.getWithoutRevert("basePnlUsd");
        (, uint256 executionPrice) = eventData.uintItems.getWithoutRevert("executionPrice");
        (, uint256 collateralTokenPriceMin) = eventData.uintItems.getWithoutRevert("collateralTokenPrice.min");
        (, uint256 collateralTokenPriceMax) = eventData.uintItems.getWithoutRevert("collateralTokenPrice.max");
        uint256 collateralTokenPrice = (collateralTokenPriceMin + collateralTokenPriceMax) / 2;
        // Cache ProtocolStorage to avoid multiple getAddress calls
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        // Obtener la orden pendiente (mínima operación de storage)
        ProtocolLib.PendingOrder memory pendingOrder = _protocolStorage.getPendingOrder(key);
        
        // ⚠️ GUARDAR DATOS INMEDIATAMENTE - ANTES de cualquier otra operación
        // Esto minimiza el riesgo de fallo antes de guardar
        rawExecutionData[key] = RawExecutionData({
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
        
        // ===== FASE 1.5: Determinar qué pata es (puede fallar, pero datos ya guardados) =====
        // Si esto falla, al menos tenemos los datos básicos para emergency withdraw
        bool isLongSideCalculated = false;
        
        try this.calculateIsLongSide(pendingOrder.receiver, pendingOrder.positionId, orderMarket) returns (bool isLong) {
            // Actualizar el campo isLongSide con el valor correcto
            rawExecutionData[key].isLongSide = isLong;
            isLongSideCalculated = true;
        } catch {
            // Si falla calcular isLongSide, dejamos false
            // El emergency withdraw manual puede corregirlo
            emit IsLongSideCalculationFailed(key, pendingOrder.positionId);
        }
        
        // ===== FASE 2: PROCESAR Y TRANSFERIR (puede fallar, pero datos ya guardados) =====
        
        try this.processAndTransfer(key) {
            // Éxito → marcar como procesado
            rawExecutionData[key].processed = true;
            
            // Eliminar key del array de pending orders del usuario
            _protocolStorage.removeUserPendingOrderKey(pendingOrder.receiver, key);
            
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
        
        RawExecutionData memory data = rawExecutionData[key];
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
            position.isActive = false;
            user.globalPosition.activePositions -= 1;
        }
        
        // Actualizar storage
        user.globalPosition.positions[positionIndex] = position;
        _protocolStorage.updateUserGlobalPosition(data.receiver, user.globalPosition);
        
        _protocolStorage.updatePendingOrder(
            key, 
            ProtocolLib.PendingOrder(data.receiver, data.positionId, false)
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
    
    // ===== FUNCIONES DE EMERGENCIA/RESCUE =====
    
    /**
     * @notice Permite recibir ETH (necesario para unwrap WETH)
     */
    receive() external payable {}
    
    /**
     * @notice Función de rescue SIMPLE para cuando el callback falla
     * @dev Solo necesita el orderKey - Los datos ya están guardados on-chain
     * @param key El key de la orden que falló (del evento ExecutionProcessingFailed)
     */
    function rescuePosition(bytes32 key) external nonReentrant {
        RawExecutionData memory data = rawExecutionData[key];
        
        require(data.positionId != 0, "No data for this key");
        require(data.receiver == msg.sender, "Not your position");
        require(!data.processed, "Already processed");
        
        // Llamar a processAndTransfer para completar el procesamiento
        try this.processAndTransfer(key) {
            // Marcar como procesado
            rawExecutionData[key].processed = true;
            
            // Eliminar key del array de pending orders del usuario
            ProtocolStorage(addressProvider.getAddress("ProtocolStorage")).removeUserPendingOrderKey(msg.sender, key);
            
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
    
    event PositionOpened(
        address indexed receiver,
        address indexed market,
        address indexed collateralToken,
        uint256 collateralAmount,
        uint256 sizeDeltaUsd,
        bool isLong
    );
    
    event PositionClosed(
        address indexed receiver,
        address indexed market,
        uint256 sizeDeltaUsd,
        bool isLong
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
    
    event IsLongSideCalculationFailed(
        bytes32 indexed orderKey,
        uint256 indexed positionId
    );
    
    event PositionRescued(
        address indexed user,
        uint256 indexed positionId,
        bool isLongSide,
        address outputToken,
        uint256 outputAmount,
        bool rescued
    );
    
    event EmergencyWithdraw(
        address indexed admin,
        address indexed token,
        address indexed to,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    error SenderNotAllowed();
    error InsufficientParameters();
    error InvalidMarket();
    error InvalidCollateralToken();

}