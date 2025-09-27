//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";
import { DecoderLib } from "../../../lib/Decoder.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";

interface IExchangeRouter {
    function createOrder(BaseOrderUtils.CreateOrderParams calldata params) external payable;
}

interface IOrderVault {
    function transferIn(address token, address from, uint256 amount) external;
}

library BaseOrderUtils {
    struct CreateOrderParams {
        CreateOrderParamsAddresses addresses;
        CreateOrderParamsNumbers numbers;
        OrderType orderType;
        DecreasePositionSwapType decreasePositionSwapType;
        bool isLong;
        bool shouldUnwrapNativeToken;
        bool autoCancel;
        bytes32 referralCode;
    }

    struct CreateOrderParamsAddresses {
        address receiver;
        address cancellationReceiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialCollateralToken;
        address[] swapPath;
    }

    struct CreateOrderParamsNumbers {
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
    }

    enum OrderType {
        MarketSwap,
        LimitSwap,
        MarketIncrease,
        LimitIncrease,
        MarketDecrease,
        LimitDecrease,
        StopLossDecrease
    }

    enum DecreasePositionSwapType {
        NoSwap,
        SwapPnlTokenToCollateralToken,
        SwapCollateralTokenToPnlToken
    }
}

contract MarketNeutral {
    using SafeERC20 for IERC20;

    Roles public immutable roles;
    
    IExchangeRouter public immutable exchangeRouter;
    IOrderVault public immutable orderVault;
    
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    
    constructor(address _roles, address _exchangeRouter, address _orderVault) {
        roles = Roles(_roles);
        exchangeRouter = IExchangeRouter(_exchangeRouter);
        orderVault = IOrderVault(_orderVault);
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function execute(uint8 functionId, bytes[] calldata _data) external onlyProtocol {
        if(functionId == 0) {
            ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
            openPosition(params);
        } else if(functionId == 1) {
            ProtocolLib.DeFiParam[] memory params = DecoderLib.decoder(_data);
            closePosition(params);
        }
    }

    function openPosition(ProtocolLib.DeFiParam[] memory _params) internal {
                
        address market = _params[0].w;
        address collateralToken = _params[1].w;
        uint256 collateralAmount = _params[2].x;
        uint256 sizeDeltaUsd = _params[3].x;
        uint256 acceptablePrice = _params[4].x;
        uint256 executionFee = _params[5].x;
        address receiver = _params[6].w;
        
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        IERC20(collateralToken).forceApprove(address(orderVault), collateralAmount);
        orderVault.transferIn(collateralToken, address(this), collateralAmount);
        
        BaseOrderUtils.CreateOrderParams memory orderParams = BaseOrderUtils.CreateOrderParams({
            addresses: BaseOrderUtils.CreateOrderParamsAddresses({
                receiver: receiver,
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: market,
                initialCollateralToken: collateralToken,
                swapPath: new address[](0)
            }),
            numbers: BaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: sizeDeltaUsd,
                initialCollateralDeltaAmount: collateralAmount,
                triggerPrice: 0,
                acceptablePrice: acceptablePrice,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0
            }),
            orderType: BaseOrderUtils.OrderType.MarketIncrease,
            decreasePositionSwapType: BaseOrderUtils.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(0)
        });
        
        exchangeRouter.createOrder{value: executionFee}(orderParams);
        
        emit PositionOpened(receiver, market, collateralToken, collateralAmount, sizeDeltaUsd, true);
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

    function closePosition(ProtocolLib.DeFiParam[] memory _params) internal {

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

}