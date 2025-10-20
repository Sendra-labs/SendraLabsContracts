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

contract TestMarketNeutral is ReentrancyGuard {
    using SafeERC20 for IERC20;

    Roles public immutable roles;
    
    IExchangeRouter public immutable exchangeRouter;
    IOrderVault public immutable orderVault;
    
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    
    constructor(/*address _roles, address _exchangeRouter, address _orderVault*/) {
        //roles = Roles(_roles);
        exchangeRouter = IExchangeRouter(0x87d66368cD08a7Ca42252f5ab44B2fb6d1Fb8d15);//IExchangeRouter(_exchangeRouter);
        orderVault = IOrderVault(0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5);//IOrderVault(_orderVault);
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }
/*
    function execute(uint8 functionId, bytes[] calldata _data) external onlyProtocol {
        if(functionId == 0) {
            ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
            openPosition(params);
        } else if(functionId == 1) {
            ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
            closePosition(params);
        }
    }
*/

    function openPosition1 (
        address collateralToken,
        uint256 collateralAmount
    ) public {        
        
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(collateralToken).safeTransfer(address(orderVault), collateralAmount);
        
    }
/*
    // sizeDelta,trigger y acceptable es con el https://github.com/gmx-io/gmx-synthetics/blob/e9c918135065001d44f24a2a329226cf62c55284/utils/math.ts#L52
    function openPosition3 (
        address collateralToken,
        uint256 collateralAmount,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 executionFee,
        address initialToken,
        address[] memory _path,
        uint256 _trigger
    ) public payable{

        address market = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
        address receiver = 0x7F4C831de10684f85867899708cB49FfbF4983B9; 
        
        // swapPath vacío para usar initialCollateralToken directamente
        address[] memory emptyPath = new address[](0);

        // Transferir el collateral al orderVault
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(collateralToken).safeTransfer(address(orderVault), collateralAmount);
        
        // Crear los parámetros de la orden directamente
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver, // Usar el mismo receiver para cancelación
                callbackContract: address(0), 
                uiFeeReceiver: address(0), 
                market: market,
                initialCollateralToken: initialToken,
                swapPath: emptyPath // Array vacío para usar initialCollateralToken directamente
            }),
            numbers: BaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd, // Ya viene con 30 decimales
                initialCollateralDeltaAmount: collateralAmount, // Usar el monto real del collateral
                triggerPrice: _trigger, 
                acceptablePrice: acceptablePrice, // Ya viene con 12 decimales
                executionFee: executionFee,
                callbackGasLimit: 200000, 
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: BaseOrderUtils.OrderType.MarketIncrease, // 2 = MarketIncrease
            decreasePositionSwapType: BaseOrderUtils.DecreasePositionSwapType.NoSwap,
            isLong: true, 
            shouldUnwrapNativeToken: false, 
            autoCancel: false,
            referralCode: bytes32(0)
        });
        
        // Llamar createOrder con el execution fee como value
        exchangeRouter.createOrder{value: executionFee}(orderParams);
        
        emit PositionOpened(receiver, market, collateralToken, collateralAmount, sizeDeltaUsd, true);
    }
*/
    function calculateLeverage(uint256 collateralAmount, uint256 sizeDeltaUsd) public pure returns (uint256) {
        if (collateralAmount == 0) return 0;
        
        // sizeDeltaUsd usa 30 decimales, collateralAmount usa 18 decimales
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e30; 
        
        return (adjustedSizeDelta * 1e18) / collateralAmount;
    }
  
    function calculateCollateralForLeverage(uint256 sizeDeltaUsd, uint256 leverage) public pure returns (uint256) {
        if (leverage == 0) return 0;
        
        uint256 adjustedSizeDelta = sizeDeltaUsd / 1e30; // 30 decimales para sizeDeltaUsd
        
        return (adjustedSizeDelta * 1e18) / leverage;
    }



    function closePosition(ProtocolLib.DeFiParam[] memory _params) public {

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

    error SenderNotAllowed();
    error InsufficientParameters();
    error InvalidMarket();
    error InvalidCollateralToken();


    function openPositionWithETH(
        uint256 wethAmount,           
        uint256 sizeDeltaUsd,         
        uint256 acceptablePrice,      
        uint256 executionFee          
    ) public payable nonReentrant {
        address market = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
        address receiver = 0x7F4C831de10684f85867899708cB49FfbF4983B9;
        
        // Transferir WETH del usuario (collateral + execution fee)
        uint256 totalWethNeeded = wethAmount + executionFee;        
                
        address[] memory emptyPath = new address[](0);
        
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: receiver,
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: WETH,
                swapPath: emptyPath
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
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0),
            dataList: new bytes32[](0)
        });
        
        bytes[] memory multicallData = new bytes[](2);
        
        // 1. sendWnt para enviar WETH (collateral + execution fee) al vault
        multicallData[0] = abi.encodeCall(
            IExchangeRouter.sendWnt,
            (address(orderVault), totalWethNeeded)
        );
        
        multicallData[1] = abi.encodeCall(
            IExchangeRouter.createOrder,
            (orderParams)
        );
        
        exchangeRouter.multicall{value: msg.value}(multicallData);
        
        emit PositionOpened(receiver, market, WETH, wethAmount, sizeDeltaUsd, true);
    }


}