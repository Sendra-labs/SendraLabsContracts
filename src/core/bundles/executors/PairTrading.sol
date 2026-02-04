/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒                                                                                                                                                    
________________________________________________________________
*/

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
import { PricesLib } from "../../../lib/Prices.lib.sol";
import { GMXMarketsRegistry } from "../../../core/config/gmxMarkets.sol";
import { PairTradingLib } from "../../../lib/PairTrading/PairTradingLib.sol";
import { PairTradingStorage } from "../storage/PairTradingStorage.sol";
import { IWETH } from "../../../interfaces/IWETH.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { PositionInitializer } from "./PositionInitializer.sol";

/**
 * @title PairTrading
 * @author 
 * @notice Executor contract for market neutral trading strategies on GMX
 * @dev This contract enables users to open simultaneous long and short positions
 *      in different markets to create market-neutral strategies. It supports both
 *      ETH and USDC as collateral tokens. The contract handles position initialization,
 *      order creation on GMX, and position closure through callbacks.
 * 
 *      Key features:
 *      - Market neutral position opening (long + short simultaneously)
 *      - Support for ETH and USDC collateral
 *      - Position closing with callback handling
 *      - Slippage protection via acceptable price calculations
 *      - Automatic position key generation and storage
 */
contract PairTrading is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /**
     * @notice Constructs the PairTrading contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    /**
     * @notice Modifier to restrict function access to protocol contracts only
     * @dev Checks if the caller is a registered protocol contract via Roles
     */
    modifier onlyProtocol() {
        if(!Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    /**
     * @notice Opens a market neutral strategy using ETH as collateral
     * @dev Divides the provided ETH equally into two parts and simultaneously opens:
     *      - A long position in the specified market (_input.marketLong)
     *      - A short position in the specified market (_input.marketShort)
     * 
     *      The function calculates acceptable prices with slippage, initializes position
     *      data in protocol storage, and executes both orders on GMX.
     * 
     * @param _input Input parameters containing:
     *        - totalEthAmount: Total amount of ETH to be divided between long and short
     *        - marketLong: Market identifier for the long position
     *        - marketShort: Market identifier for the short position
     *        - sizeDeltaUsdLong: Size of the long position in USD
     *        - sizeDeltaUsdShort: Size of the short position in USD
     *        - slippageBps: Allowed slippage in basis points (1 = 0.01%)
     *        - executionFee: Execution fee for each order on GMX
     * 
     * @custom:require msg.value >= (totalEthAmount / 2 + executionFee) * 2
     *           The sent value must cover half of ETH for each position plus execution fee for both orders
     * 
     * @custom:emit PositionOpened Emitted twice, once for each opened position (long and short)
     */
    function openEtherPairTrading(PairTradingLib.EtherPairTradingInput calldata _input) public payable {
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices")); //OPTIMIZATION
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets")); //OPTIMIZATION

        (uint256 aceptablePriceLong,) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketLong), true, true, _input.slippageBps);
        (uint256 aceptablePriceShort,) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketShort), false, true, _input.slippageBps);
        
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

        address weth = addressProvider.getAddress("WETH"); //OPTIMIZATION
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
        uint256 totalValueNeeded = _value * 2; 
        
        require(msg.value >= totalValueNeeded, "Insufficient msg.value");
        
        initializePosition(newPositionData, 0);
        
        PairTradingLib.EtherOneSideTradeInput memory longInput = PairTradingLib.EtherOneSideTradeInput({
            ethAmount: _input.totalEthAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdLong,
            acceptablePrice: aceptablePriceLong,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketLong,
            isLong: true,
            receiver: msg.sender
        });
        
        PairTradingLib.EtherOneSideTradeInput memory shortInput = PairTradingLib.EtherOneSideTradeInput({
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

    /**
     * @notice Opens a market neutral strategy using USDC as collateral
     * @dev Divides the provided USDC equally into two parts and simultaneously opens:
     *      - A long position in the specified market (_input.marketLong)
     *      - A short position in the specified market (_input.marketShort)
     * 
     *      The function calculates acceptable prices with slippage, transfers USDC from
     *      the user, initializes position data in protocol storage, and executes both
     *      orders on GMX.
     * 
     * @param _input Input parameters containing:
     *        - totalUsdcAmount: Total amount of USDC to be divided between long and short
     *        - marketLong: Market identifier for the long position
     *        - marketShort: Market identifier for the short position
     *        - sizeDeltaUsdLong: Size of the long position in USD
     *        - sizeDeltaUsdShort: Size of the short position in USD
     *        - slippageBps: Allowed slippage in basis points (1 = 0.01%)
     *        - executionFee: Execution fee for each order on GMX
     * 
     * @custom:require User must have approved this contract to spend totalUsdcAmount USDC
     * @custom:require msg.value >= executionFee * 2
     *           The sent value must cover execution fees for both orders
     * 
     * @custom:emit PositionOpened Emitted twice, once for each opened position (long and short)
     */
    function openUSDCPairTrading(PairTradingLib.UsdcPairTradingInput calldata _input) public payable {
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        // metemos transfer de USDC entry fee aqui 0.1% if(entry fee isActivated)
        // que salga de _input.totalUsdcAmount y se envie a nuestra tesorería. Frontend tendrá que approve y enviar el 0.1% de más.
        (uint256 aceptablePriceLong, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketLong), true, true, _input.slippageBps);
        (uint256 aceptablePriceShort, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(gmxMarkets.getMarket(_input.marketShort), false, true, _input.slippageBps);
        
        bytes[] memory newPositionData = new bytes[](18);
        newPositionData[0] = abi.encode(_input.totalUsdcAmount);
        newPositionData[1] = abi.encode(false); // isNativeToken = false if is USDC
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
        newPositionData[14] = abi.encode(int256(0));  // PNL  we can Delete This One

        address usdc = addressProvider.getAddress("USDC");
        bytes32 longKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketLong), usdc, true);
        bytes32 shortKey = calculatePositionKey(address(this), gmxMarkets.getMarket(_input.marketShort), usdc, false);
        
        newPositionData[15] = abi.encode(longKey);   // longKey
        newPositionData[16] = abi.encode(shortKey);  // shortKey
        newPositionData[17] = abi.encode(address(this));  // proxy address
    
        /*__  pair trading positionParams  __*/
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
        /// NOT YET BUT MUST BE ADDED:
        // position is copied from 'address' ALPHA COPY
        // Stop Loss && Take Profit
        // Close date long && close date short


        uint256 _value = msg.value / 2;
        initializePosition(newPositionData, 0);
        
        PairTradingLib.UsdcOneSideTradeInput memory longInput = PairTradingLib.UsdcOneSideTradeInput({
            usdcAmount: _input.totalUsdcAmount / 2,
            sizeDeltaUsd: _input.sizeDeltaUsdLong,
            acceptablePrice: aceptablePriceLong,
            executionFee: _input.executionFee,
            value: _value,
            market: _input.marketLong,
            isLong: true,
            receiver: msg.sender
        });
        
        PairTradingLib.UsdcOneSideTradeInput memory shortInput = PairTradingLib.UsdcOneSideTradeInput({
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

    /**
     * @notice Initializes a new position in protocol storage
     * @dev Delegates position initialization to the PositionInitializer contract
     * @param _newPositionData Array of encoded position parameters
     * @param _positionType Type identifier for the position (0 for market neutral)
     */
    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType) internal {
        PositionInitializer positionInitializer = PositionInitializer(addressProvider.getAddress("PositionInitializer"));
        positionInitializer.initializePosition(_newPositionData, _positionType, msg.sender);
    }

    /**
     * @notice Opens a single position using ETH as collateral on GMX
     * @dev Creates a market increase order on GMX ExchangeRouter. The ETH is wrapped to WETH
     *      and sent to GMX OrderVault along with the execution fee. The order is created as
     *      a MarketIncrease order type.
     * 
     * @param _input Input parameters containing:
     *        - ethAmount: Amount of ETH to use as collateral
     *        - sizeDeltaUsd: Size of the position in USD
     *        - acceptablePrice: Maximum/minimum acceptable price depending on direction
     *        - executionFee: Fee paid to GMX for order execution
     *        - value: Total ETH value to send (ethAmount + executionFee)
     *        - market: Market identifier
     *        - isLong: Whether this is a long (true) or short (false) position
     *        - receiver: Address that will receive the position
     * 
     * @custom:emit PositionOpened Emitted when the order is successfully created
     */
    function openPositionWithEther(PairTradingLib.EtherOneSideTradeInput memory _input) public payable {

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

    /**
     * @notice Opens a single position using USDC as collateral on GMX
     * @dev Creates a market increase order on GMX ExchangeRouter. The USDC is transferred
     *      from the caller, approved to GMX Router, and sent to GMX OrderVault. If the market
     *      requires a different collateral token, a swap path is configured.
     * 
     * @param _input Input parameters containing:
     *        - usdcAmount: Amount of USDC to use as collateral
     *        - sizeDeltaUsd: Size of the position in USD
     *        - acceptablePrice: Maximum/minimum acceptable price depending on direction
     *        - executionFee: Fee paid to GMX for order execution
     *        - value: ETH value to send for execution fee
     *        - market: Market identifier
     *        - isLong: Whether this is a long (true) or short (false) position
     *        - receiver: Address that will receive the position
     * 
     * @custom:require User must have approved this contract to spend usdcAmount USDC
     * 
     * @custom:emit PositionOpened Emitted when the order is successfully created
     */
    function openPositionWithUSDC(PairTradingLib.UsdcOneSideTradeInput memory _input) public payable {

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
        IERC20(usdc).approve(_router, usdcAmount); // We can do an infinite approval in the PROXIES constructor for gas optimization or Approve just one time in the openUSDCPairTrading function 
        
        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: usdc,
                swapPath: getSwapPath(market, usdc, gmxMarkets, true) // I think every available market has USDC as collateral token, we can remove this function.
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

    /**
     * @notice Calculates the swap path for collateral token conversion
     * @dev Returns an empty array if no swap is needed, otherwise returns a 2-token path
     *      for swapping between the initial collateral token and the market's required collateral token
     * 
     * @param _market Address of the GMX market
     * @param _initialCollateralToken The collateral token being provided (WETH or USDC)
     * @param _gmxMarkets GMXMarketsRegistry instance to query market collateral token
     * @param isIncrease Whether this is for opening (true) or closing (false) a position
     * 
     * @return swapPath Array of token addresses for the swap path:
     *         - Empty array if no swap needed
     *         - [initialCollateralToken, marketCollateralToken] for increase orders
     *         - [marketCollateralToken, initialCollateralToken] for decrease orders
     */
    function getSwapPath(
        address _market, 
        address _initialCollateralToken,
        GMXMarketsRegistry _gmxMarkets,
        bool isIncrease
    ) public view returns (address[] memory) {
        address collateralToken = _gmxMarkets.getMarketCollateralTokenByAddress(_market);
        if (collateralToken == address(0)) {
            return new address[](0);
        } else {
            if (isIncrease) {
                address[] memory swapPath = new address[](2);
                swapPath[0] = _initialCollateralToken;
                swapPath[1] = collateralToken;
                return swapPath;
            } else {
                address[] memory swapPath = new address[](2);
                swapPath[0] = collateralToken;
                swapPath[1] = _initialCollateralToken;
                return swapPath;
            }
        }
    }

    /**
     * @notice Closes both sides of a market neutral position simultaneously
     * @dev Splits the provided execution fee equally and closes both the long and short
     *      positions associated with the given position ID. Both orders are submitted
     *      to GMX for execution.
     * 
     * @param _input Input parameters containing:
     *        - positionId: ID of the market neutral position to close
     *        - executionFee: Total execution fee to be split between both orders
     *        - slippageBps: Allowed slippage in basis points for closing
     * 
     * @custom:require msg.value >= executionFee
     *           The sent value must cover the total execution fee for both orders
     * 
     * @custom:require Position must be active
     * 
     * @custom:emit PositionClosed Emitted twice, once for each closed position (long and short)
     */
    function closePairTrading(PairTradingLib.ClosePairTradingInput calldata _input) public payable {
        uint256 _value = msg.value / 2;
        PairTradingLib.CloseSidePairTradingInput memory longSideInput = PairTradingLib.CloseSidePairTradingInput({
            positionId: _input.positionId,
            executionFee: _input.executionFee,
            slippageBps: _input.slippageBps,
            value: _value,
            isLongSide: true
        });
        PairTradingLib.CloseSidePairTradingInput memory shortSideInput = PairTradingLib.CloseSidePairTradingInput({
            positionId: _input.positionId,
            executionFee: _input.executionFee,
            slippageBps: _input.slippageBps,
            value: _value,
            isLongSide: false
        });
        closeSidePairTrading(longSideInput);
        closeSidePairTrading(shortSideInput);
    }


    function closeSidePairTrading( PairTradingLib.CloseSidePairTradingInput memory _input ) public payable {

        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address weth = addressProvider.getAddress("WETH");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(msg.sender,_input.positionId);
        if(!position.isActive) {
            revert PositionNotActive();
        }
        bytes[] memory positionData = position.positionData;

        address market = abi.decode(_input.isLongSide ? positionData[2] : positionData[3], (address));
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        (uint256 _acceptablePrice, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(
            market,
            _input.isLongSide, 
            false, 
            10000 // hardcoded for testing
        ); // AQUI FALLA SI VA CON OTRO SLIPPAGE BPS que no sea 10000... habiendo metido el update del minimumOutputAmount
            // Creo que solo Falla el LONG
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

        uint256 minOutputAmount = getMinOutputAmount(market, position, gmxPrices, _input.slippageBps, isLong);

        uint256 callbackGasLimit = 1250000; // 1.25M gas
        address callbackContract = addressProvider.getAddress("ClosePositionCallbacks");

    
        address[] memory decreaseSwapPath;
        if (isLong) {
            decreaseSwapPath = new address[](1);
            decreaseSwapPath[0] = market;
        }

        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver:  callbackContract,
                cancellationReceiver: receiver,
                callbackContract: callbackContract,
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: collateralToken,
                swapPath: decreaseSwapPath
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: callbackGasLimit, 
                minOutputAmount: minOutputAmount,
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

        PairTradingStorage(addressProvider.getAddress("PairTradingStorage")).updatePendingOrder(key, PairTradingLib.PendingOrder(receiver, address(this), positionId, true));
        
        PairTradingStorage(addressProvider.getAddress("PairTradingStorage")).addUserPendingOrderKey(receiver, key);

        emit PositionClosed(receiver, market, sizeDeltaUsd, isLong); 
    }

    /**
     * @notice Submits a stop-loss decrease order for one side (long or short) of a pair position.
     * @dev Order executes when oracle price crosses triggerPrice: long when price <= triggerPrice, short when price >= triggerPrice.
     * @param _input positionId, executionFee, slippageBps, value, triggerPrice (GMX format, 30 decimals), isLongSide
     * @custom:require msg.value >= executionFee
     */
    function closeSidePairTradingWithStopLoss( PairTradingLib.CloseSidePairTradingInputWithStopLoss memory _input ) public payable {

        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address weth = addressProvider.getAddress("WETH");
        address usdc = addressProvider.getAddress("USDC");
        address orderVault = addressProvider.getAddress("OrderVaultGMX");
        address exchangeRouter = addressProvider.getAddress("ExchangeRouterGMX");
        
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(msg.sender,_input.positionId);
        if(!position.isActive) {
            revert PositionNotActive();
        }
        bytes[] memory positionData = position.positionData;

        address market = abi.decode(_input.isLongSide ? positionData[2] : positionData[3], (address));
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));
        (uint256 _acceptablePrice, /*closePositionPrice*/) = gmxPrices.getAcceptablePrice(
            market,
            _input.isLongSide, 
            false, 
            10000 // hardcoded for testing
        ); // AQUI FALLA SI VA CON OTRO SLIPPAGE BPS que no sea 10000... habiendo metido el update del minimumOutputAmount
            // Creo que solo Falla el LONG
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

        uint256 minOutputAmount = getMinAmountForStopLoss(position, _input.triggerPrice, _input.slippageBps, isLong);

        uint256 callbackGasLimit = 1250000; // 1.25M gas
        address callbackContract = addressProvider.getAddress("ClosePositionCallbacks");

    
        address[] memory decreaseSwapPath;
        if (isLong) {
            decreaseSwapPath = new address[](1);
            decreaseSwapPath[0] = market;
        }

        IBaseOrderUtils.CreateOrderParams memory orderParams = IBaseOrderUtils.CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver:  callbackContract,
                cancellationReceiver: receiver,
                callbackContract: callbackContract,
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: collateralToken,
                swapPath: decreaseSwapPath
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: 0,
                triggerPrice: _input.triggerPrice,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: callbackGasLimit, 
                minOutputAmount: minOutputAmount,
                validFromTime: 0
            }),
            orderType: Order.OrderType.StopLossDecrease,
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

        PairTradingStorage(addressProvider.getAddress("PairTradingStorage")).updatePendingOrder(key, PairTradingLib.PendingOrder(receiver, address(this), positionId, true));
        
        PairTradingStorage(addressProvider.getAddress("PairTradingStorage")).addUserPendingOrderKey(receiver, key);

        emit PositionClosed(receiver, market, sizeDeltaUsd, isLong); 
    }
    
    // read Functions

    /**
     * @notice Calculates the minimum output amount when closing a position
     * @dev Computes the expected output value based on price changes and applies slippage
     *      protection. For short positions, returns 0 if price has doubled or more.
     *      Uses a default slippage of 200 bps (2%) if slippageBps is 10000.
     * 
     * @param market Address of the GMX market
     * @param position The position data containing initial values and prices
     * @param gmxPrices GMXPrices instance to query current market price
     * @param _slippageBps Allowed slippage in basis points (10000 = use default 200 bps)
     * @param isLong Whether this is for a long (true) or short (false) position
     * 
     * @return minOutputAmount Minimum acceptable output amount in USDC (6 decimals)
     *         Returns 0 for short positions if currentPrice >= initialPrice * 2
     */
    function getMinOutputAmount(address market, ProtocolLib.Position memory position, GMXPrices gmxPrices, uint256 _slippageBps, bool isLong) public view returns (uint256) {
        
        uint256 slippageBps = _slippageBps == 10000 ? 200 : _slippageBps;
        uint256 initialUsdcAmount = abi.decode(position.positionData[8], (uint256));
        uint256 initialPrice = isLong 
            ? abi.decode(position.positionData[6], (uint256))
            : abi.decode(position.positionData[7], (uint256));
        uint256 currentPrice = gmxPrices.getPrice(market);
        if (!isLong && currentPrice >= initialPrice * 2) {
            return 0;
        }
        uint256 currentUsdcAmount;
        if (isLong) {
            currentUsdcAmount = (initialUsdcAmount * currentPrice) / initialPrice;
        } else {
            
            currentUsdcAmount = (initialUsdcAmount * initialPrice) / currentPrice;
        } 
        
        uint256 minUsdcAmount = (currentUsdcAmount * (10000 - slippageBps)) / 10000;
        
        // minOutputAmount should be in the same units as outputAmount (USDC base units with 6 decimals)
        // GMX validates: outputUsd = outputAmount * outputTokenPrice
        // where outputAmount is in token units (6 decimals for USDC) and outputTokenPrice is in GMX format (30 decimals)
        // The comment says minOutputAmount is treated as USD value, but since outputAmount is in token units,
        // we keep minOutputAmount in the same units (USDC with 6 decimals) to match outputAmount
        uint256 minOutputAmount = minUsdcAmount;
        
        return minOutputAmount;
    }

    /**
     * @notice Minimum output amount when closing at a given trigger price (e.g. stop loss).
     * @dev Same logic as getMinOutputAmount but uses triggerPrice instead of current market price.
     *      triggerPrice must be in GMX format (30 decimals); it is normalized to 8 decimals to match initialPrice.
     *
     * @param position The position data (initialPrice and initial USDC value)
     * @param triggerPrice Execution price in GMX format (30 decimals)
     * @param _slippageBps Slippage in basis points (10000 = use default 200 bps)
     * @param isLong Whether this is for a long (true) or short (false) position
     * @return minOutputAmount Minimum acceptable output in USDC (6 decimals)
     */
    function getMinAmountForStopLoss(
        ProtocolLib.Position memory position,
        uint256 triggerPrice,
        uint256 _slippageBps,
        bool isLong
    ) public pure returns (uint256) {
        uint256 slippageBps = _slippageBps == 10000 ? 200 : _slippageBps;
        uint256 initialUsdcAmount = abi.decode(position.positionData[8], (uint256));
        uint256 initialPrice = isLong
            ? abi.decode(position.positionData[6], (uint256))
            : abi.decode(position.positionData[7], (uint256));
        // GMX trigger price is 30 decimals; initialPrice is 8 decimals (Chainlink)
        uint256 executionPrice8 = triggerPrice / 1e22;
        if (!isLong && executionPrice8 >= initialPrice * 2) {
            return 0;
        }
        uint256 usdcAtTrigger;
        if (isLong) {
            usdcAtTrigger = (initialUsdcAmount * executionPrice8) / initialPrice;
        } else {
            usdcAtTrigger = (initialUsdcAmount * initialPrice) / executionPrice8;
        }
        uint256 minUsdcAmount = (usdcAtTrigger * (10000 - slippageBps)) / 10000;
        return minUsdcAmount;
    }

    /**
     * @notice Calculates the position key using keccak256(abi.encode(account, market, collateralToken, isLong))
     * @dev This key uniquely identifies a position on GMX and is used for position lookups
     * @param account Address of the account holding the position
     * @param market Address of the GMX market
     * @param collateralToken Address of the collateral token (WETH or USDC)
     * @param isLong Whether this is a long (true) or short (false) position
     * @return positionKey The calculated keccak256 hash identifying the position
     */
    function calculatePositionKey(
        address account,
        address market,
        address collateralToken,
        bool isLong
    ) public pure returns (bytes32 positionKey) {
        positionKey = keccak256(abi.encode(account, market, collateralToken, isLong));
    }

    /**
     * @notice Calculates the leverage ratio for a position
     * @dev Leverage = (sizeDeltaUsd / 1e24) * 1e18 / collateralAmount
     *      Adjusts for GMX's 30-decimal price format (sizeDeltaUsd has 30 decimals)
     * 
     * @param collateralAmount Amount of collateral in token units (with 18 decimals for ETH/WETH)
     * @param sizeDeltaUsd Position size in USD with 30 decimals (GMX format)
     * 
     * @return leverage The leverage ratio scaled by 1e18 (e.g., 1e18 = 1x, 2e18 = 2x)
     *         Returns 0 if collateralAmount is 0
     */
    function calculateLeverage(uint256 collateralAmount, uint256 sizeDeltaUsd) public pure returns (uint256) {
        if (collateralAmount == 0) return 0;
        
        
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e24; 
        
        return (adjustedSizeDelta * 1e18) / collateralAmount;
    }
  
    /**
     * @notice Calculates the required collateral amount for a target leverage
     * @dev Collateral = (sizeDeltaUsd / 1e24) * 1e18 / leverage
     *      Adjusts for GMX's 30-decimal price format (sizeDeltaUsd has 30 decimals)
     * 
     * @param sizeDeltaUsd Target position size in USD with 30 decimals (GMX format)
     * @param leverage Target leverage ratio scaled by 1e18 (e.g., 2e18 = 2x leverage)
     * 
     * @return collateralAmount Required collateral amount in token units (with 18 decimals)
     *         Returns 0 if leverage is 0
     */
    function calculateCollateralForLeverage(uint256 sizeDeltaUsd, uint256 leverage) public pure returns (uint256) {
        if (leverage == 0) return 0;
        
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e24;
        
        return (adjustedSizeDelta * 1e18) / leverage;
    }

    // events

    /**
     * @notice Emitted when a position order is successfully created on GMX
     * @param receiver Address that will receive the position ownership
     * @param market Address of the GMX market
     * @param collateralToken Address of the collateral token used
     * @param collateralAmount Amount of collateral deposited
     * @param sizeDeltaUsd Size of the position in USD
     * @param isLong Whether this is a long (true) or short (false) position
     */
    event PositionOpened(
        address indexed receiver,
        address indexed market,
        address indexed collateralToken,
        uint256 collateralAmount,
        uint256 sizeDeltaUsd,
        bool isLong
    );
    
    /**
     * @notice Emitted when a position close order is successfully created on GMX
     * @param receiver Address that will receive the returned funds
     * @param market Address of the GMX market
     * @param sizeDeltaUsd Size of the position being closed in USD
     * @param isLong Whether this is for a long (true) or short (false) position
     */
    event PositionClosed(
        address indexed receiver,
        address indexed market,
        uint256 sizeDeltaUsd,
        bool isLong
    );


    /// @notice Thrown when the caller is not authorized (not a protocol contract)
    error SenderNotAllowed();
    
    /// @notice Thrown when required parameters are missing or invalid
    error InsufficientParameters();
    
    /// @notice Thrown when an invalid market address is provided
    error InvalidMarket();
    
    /// @notice Thrown when an invalid collateral token is provided
    error InvalidCollateralToken();
    
    /// @notice Thrown when attempting to operate on an inactive position
    error PositionNotActive();
}