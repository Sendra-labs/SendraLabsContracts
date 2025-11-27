//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";
import { DecoderLib } from "../../../lib/Decoder.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { IExchangeRouter } from "../../../interfaces/GMX/IExchangeRouter.sol";
import { IOrderVault } from "../../../interfaces/GMX/IOrderVault.sol";
import { IBaseOrderUtils } from "gmx-synthetics/order/IBaseOrderUtils.sol";
import { Order } from "gmx-synthetics/order/Order.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { IOrderCallbackReceiver } from "../../../interfaces/GMX/IOrderCallbackReceiver.sol";
import { EventUtils } from "../../../lib/GMX lib/EventUtils.sol";
import { GMXPrices } from "../../../periphery/utilsGMX/GMXPrices.sol"; 
import { GMXMarketsRegistry } from "../../../core/config/gmxMarkets.sol";
import { MarketNeutralLib } from "../../../lib/MarketNeutral/MarketNeutralLib.sol";
import { MarketNeutralStorage } from "../storage/MarketNeutralStorage.sol";
import { IWETH } from "../../../interfaces/IWETH.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { PositionInitializer } from "./PositionInitializer.sol";

contract MarketNeutral is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    AddressProvider public immutable addressProvider;
    
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    modifier onlyProtocol() {
        if(!Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }
/*
    function execute(uint8 functionId, bytes[] calldata _data) external payable onlyProtocol {
        ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
        if     (functionId == 0) openPositionWithEther(params);
        else if(functionId == 1) closeSideMarketNeutral(params);
        else if(functionId == 2) openPositionWithUSDC(params);
        else if(functionId == 3) openEtherMarketNeutral(params);
        else if(functionId == 4) openUSDCMarketNeutral(params);
    }
    */

    function openEtherMarketNeutral(MarketNeutralLib.EtherMarketNeutralInput calldata _input) public payable {
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));

        (uint256 aceptablePriceLong, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketLong), true, true, _input.slippageBps);
        (uint256 aceptablePriceShort, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketShort), false, true, _input.slippageBps);
        
        bytes[] memory newPositionData = new bytes[](18);
        newPositionData[0] = abi.encode(_input.totalEthAmount);
        newPositionData[1] = abi.encode(true); // isNativeToken
        newPositionData[2] = abi.encode(gmxMarkets.getMarket(_input.marketLong));
        newPositionData[3] = abi.encode(gmxMarkets.getMarket(_input.marketShort));
        newPositionData[4] = abi.encode(_input.sizeDeltaUsdLong); 
        newPositionData[5] = abi.encode(_input.sizeDeltaUsdShort); 
        newPositionData[6] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_input.marketLong)));
        newPositionData[7] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_input.marketShort)));
        newPositionData[8] = abi.encode(_input.totalEthAmount * gmxPrices.getPrice(0x70d95587d40A2caf56bd97485aB3Eec10Bee6336)); //checkThisLine Decimals
        newPositionData[9] = abi.encode(block.timestamp);
        newPositionData[10] = abi.encode(uint256(0));  // closeDate
        newPositionData[11] = abi.encode(uint256(0));  // finalUsdValue
        newPositionData[12] = abi.encode(uint256(0));  // finalPriceTokenLong
        newPositionData[13] = abi.encode(uint256(0));  // finalPriceTokenShort
        newPositionData[14] = abi.encode(int256(0));  // PNL
        // Calcular las claves ANTES de initializePosition
        address weth = addressProvider.getAddress("WETH");
        bytes32 longKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketLong), weth, true);
        bytes32 shortKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketShort), weth, false);
        
        newPositionData[15] = abi.encode(longKey);   // longKey
        newPositionData[16] = abi.encode(shortKey);  // shortKey
        newPositionData[17] = abi.encode(address(this));  // proxy address

        /*__  market neutral positionParams  __*/
        //0  {0, totalEthAmount}
        //1  {2, isNativeToken}
        //2  {1, market Long}
        //3  {1, market Short}
        //4  {0, sizeDeltaUsdLong}
        //5  {0, sizeDeltaUsdShort}
        //6  {0, initialPriceTokenLong}
        //7  {0, initialPriceTokenShort}
        //8  {0, initialUsdValue}
        //9  {0, openDate}
        //10 {0, closeDate}
        //11 {0, finalUsdValue}
        //12 {0, finalPriceTokenLong}
        //13 {0, finalPriceTokenShort}
        //14 {0, PNL}
        //15 {2, longKey}
        //16 {2, shortKey}
        //17 {1, proxy address}

        uint256 _value = (_input.totalEthAmount / 2) + _input.executionFee;
        uint256 totalValueNeeded = _value * 2; // Value necesario para ambas llamadas
        
        // Verificar que msg.value sea suficiente
        require(msg.value >= totalValueNeeded, "Insufficient msg.value");
        
        initializePosition(newPositionData, 0);
        
        // Preparar parámetros para posición Long
        MarketNeutralLib.EtherOneSideTradeInput memory longInput = MarketNeutralLib.EtherOneSideTradeInput({
            ethAmount: _input.totalEthAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdLong,
            acceptablePrice: aceptablePriceLong,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketLong,
            isLong: true,
            receiver: msg.sender
        });
        
        // Preparar parámetros para posición Short
        MarketNeutralLib.EtherOneSideTradeInput memory shortInput = MarketNeutralLib.EtherOneSideTradeInput({
            ethAmount: _input.totalEthAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdShort,
            acceptablePrice: aceptablePriceShort,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketShort,
            isLong: false,
            receiver: msg.sender
        });
        
        openPositionWithEther(longInput);
        openPositionWithEther(shortInput);
    }

    function openUSDCMarketNeutral(MarketNeutralLib.UsdcMarketNeutralInput calldata _input) public payable {
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));

        (uint256 aceptablePriceLong, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketLong), true, true, _input.slippageBps);
        (uint256 aceptablePriceShort, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketShort), false, true, _input.slippageBps);
        
        bytes[] memory newPositionData = new bytes[](18);
        newPositionData[0] = abi.encode(_input.totalUsdcAmount);
        newPositionData[1] = abi.encode(false); // isNativeToken = false para USDC
        newPositionData[2] = abi.encode(gmxMarkets.getMarket(_input.marketLong));
        newPositionData[3] = abi.encode(gmxMarkets.getMarket(_input.marketShort));
        newPositionData[4] = abi.encode(_input.sizeDeltaUsdLong); 
        newPositionData[5] = abi.encode(_input.sizeDeltaUsdShort); 
        newPositionData[6] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_input.marketLong)));
        newPositionData[7] = abi.encode(gmxPrices.getPrice(gmxMarkets.getMarket(_input.marketShort)));
        newPositionData[8] = abi.encode(_input.totalUsdcAmount); //checkThisLine Decimals
        newPositionData[9] = abi.encode(block.timestamp);
        newPositionData[10] = abi.encode(uint256(0));  // closeDate
        newPositionData[11] = abi.encode(uint256(0));  // finalUsdValue
        newPositionData[12] = abi.encode(uint256(0));  // finalPriceTokenLong
        newPositionData[13] = abi.encode(uint256(0));  // finalPriceTokenShort
        newPositionData[14] = abi.encode(int256(0));  // PNL

        address usdc = addressProvider.getAddress("USDC");
        bytes32 longKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketLong), usdc, true);
        bytes32 shortKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketShort), usdc, false);
        
        newPositionData[15] = abi.encode(longKey);   // longKey
        newPositionData[16] = abi.encode(shortKey);  // shortKey
        newPositionData[17] = abi.encode(address(this));  // proxy address
    
        /*__  market neutral positionParams  __*/
        //0  {0, totalUsdcAmount}
        //1  {2, isNativeToken = false}
        //2  {1, market Long}
        //3  {1, market Short}
        //4  {0, sizeDeltaUsdLong}
        //5  {0, sizeDeltaUsdShort}
        //6  {0, initialPriceTokenLong}
        //7  {0, initialPriceTokenShort}
        //8  {0, initialUsdValue}
        //9  {0, openDate}
        //10 {0, closeDate}
        //11 {0, finalUsdValue}
        //12 {0, finalPriceTokenLong}
        //13 {0, finalPriceTokenShort}
        //14 {0, PNL}
        //15 {2, longKey}
        //16 {2, shortKey}
        //17 {1, proxy address}

        uint256 _value = msg.value / 2;
        initializePosition(newPositionData, 0);
        
        // Preparar parámetros para posición Long
        MarketNeutralLib.UsdcOneSideTradeInput memory longInput = MarketNeutralLib.UsdcOneSideTradeInput({
            usdcAmount: _input.totalUsdcAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdLong,
            acceptablePrice: aceptablePriceLong,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketLong,
            isLong: true,
            receiver: msg.sender
        });
        
        // Preparar parámetros para posición Short
        MarketNeutralLib.UsdcOneSideTradeInput memory shortInput = MarketNeutralLib.UsdcOneSideTradeInput({
            usdcAmount: _input.totalUsdcAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdShort,
            acceptablePrice: aceptablePriceShort,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketShort,
            isLong: false,
            receiver: msg.sender
        });
        
        openPositionWithUSDC(longInput);
        openPositionWithUSDC(shortInput);
    }

    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType) internal {
        PositionInitializer positionInitializer = PositionInitializer(addressProvider.getAddress("PositionInitializer"));
        positionInitializer.initializePosition(_newPositionData, _positionType, msg.sender);
    }

    function openPositionWithEther(MarketNeutralLib.EtherOneSideTradeInput memory _input) public payable {

        uint256 ethAmount = _input.ethAmount;            
        uint256 sizeDeltaUsd = _input.sizeDeltaUsd;         
        uint256 acceptablePrice = _input.acceptablePrice;      
        uint256 executionFee = _input.executionFee;
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address market = gmxMarkets.getMarket(_input.market);
        bool isLong = _input.isLong;
        address receiver = _input.receiver;

        uint256 totalEthNeeded = ethAmount + executionFee;
        
        address weth = addressProvider.getAddress("WETH");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");        
        
        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: weth,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
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
        
        IExchangeRouter(addressProvider.getAddress("ExchangeRouterGMX")).multicall{value: _input.value}(multicallData);
        
        emit PositionOpened(receiver, market, weth, ethAmount, sizeDeltaUsd, isLong);
    }

    function openPositionWithUSDC(MarketNeutralLib.UsdcOneSideTradeInput memory _input) public payable {

        uint256 usdcAmount = _input.usdcAmount;
        uint256 sizeDeltaUsd = _input.sizeDeltaUsd;
        uint256 acceptablePrice = _input.acceptablePrice;
        uint256 executionFee = _input.executionFee;
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address market = gmxMarkets.getMarket(_input.market);
        bool isLong = _input.isLong;
        address receiver = msg.sender;
        
        address _exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        address _router = addressProvider.getAddress("RouterGMX");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        
        IERC20(usdc).transferFrom(msg.sender, address(this), usdcAmount);
        IERC20(usdc).approve(_router, usdcAmount);
        
        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: usdc,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: usdcAmount,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
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

    function closeMarketNeutral(MarketNeutralLib.CloseMarketNeutralInput calldata _input) public payable {
        uint256 _value = msg.value / 2;
        MarketNeutralLib.CloseSideMarketNeutralInput memory longSideInput = MarketNeutralLib.CloseSideMarketNeutralInput({
            positionId: _input.positionId,
            executionFee: _input.executionFee,
            slippageBps: _input.slippageBps,
            value: _value,
            isLongSide: true
        });
        MarketNeutralLib.CloseSideMarketNeutralInput memory shortSideInput = MarketNeutralLib.CloseSideMarketNeutralInput({
            positionId: _input.positionId,
            executionFee: _input.executionFee,
            slippageBps: _input.slippageBps,
            value: _value,
            isLongSide: false
        });
        closeSideMarketNeutral(longSideInput);
        closeSideMarketNeutral(shortSideInput);
    }


    function closeSideMarketNeutral( MarketNeutralLib.CloseSideMarketNeutralInput memory _input ) public payable {

        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address weth = addressProvider.getAddress("WETH");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        
        ProtocolLib.User memory userData = _protocolStorage.getUser(msg.sender);
        (ProtocolLib.Position memory position, ) = _protocolStorage.getUserPosition(userData.globalPosition.positions, _input.positionId);
        bytes[] memory positionData = position.positionData;

        address market = abi.decode(_input.isLongSide ? positionData[2] : positionData[3], (address));
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        (uint256 _acceptablePrice, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(
            market,
            _input.isLongSide, 
            false, 
            _input.slippageBps
        );

        uint256 sizeDeltaUsd = abi.decode(_input.isLongSide ? positionData[4] : positionData[5], (uint256));
        uint256 acceptablePrice = _acceptablePrice;      
        uint256 executionFee = _input.executionFee;  
        address receiver = msg.sender;
        bool isLong = _input.isLongSide;
        uint256 positionId = _input.positionId;
        
        // isNativeToken from positionData[1]
        // if true → WETH, if false → USDC
        bool isNativeToken = abi.decode(position.positionData[1], (bool));
        address collateralToken = isNativeToken ? weth : usdc;
        
        uint256 callbackGasLimit = 1250000; // 1.5M gas - ajustar según MAX_CALLBACK_GAS_LIMIT de GMX

        address callbackContract = addressProvider.getAddress("ClosePositionCallbacks");
        
        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver:  callbackContract, // Funds come to the contract first (for security in callbacks)
                cancellationReceiver: receiver,
                callbackContract: callbackContract, // afterOrderExecution() para actualizar storage y transferir fondos
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: collateralToken, 
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd, //-
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: callbackGasLimit, 
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: isLong,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0),
            dataList: new bytes32[](0)
        });

        IExchangeRouter exchangeRouterInstance = IExchangeRouter(exchangeRouter);

        exchangeRouterInstance.sendWnt{value: executionFee}(orderVault, executionFee);
        
        bytes32 key = exchangeRouterInstance.createOrder(orderParams);

        MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).updatePendingOrder(key, MarketNeutralLib.PendingOrder(receiver, address(this), positionId, true));
        
        MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage")).addUserPendingOrderKey(receiver, key);

        emit PositionClosed(receiver, market, sizeDeltaUsd, isLong); 
    }
    
    // read Functions

    /**
     * @notice Calcula la clave de posición usando keccak256(abi.encode(account, market, collateralToken, isLong))
     * @param account Dirección del contrato (msg.sender)
     * @param market Dirección del mercado
     * @param collateralToken Token de colateral (WETH o USDC)
     * @param isLong Si es posición long o short
     * @return positionKey La clave calculada
     */
    function calculatePositionKey(
        address account,
        address market,
        address collateralToken,
        bool isLong
    ) public pure returns (bytes32 positionKey) {
        positionKey = keccak256(abi.encode(account, market, collateralToken, isLong));
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

    // events

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


    error SenderNotAllowed();
    error InsufficientParameters();
    error InvalidMarket();
    error InvalidCollateralToken();

}