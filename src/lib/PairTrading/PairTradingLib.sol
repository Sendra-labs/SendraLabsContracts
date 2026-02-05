//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library PairTradingLib {

    struct EtherPairTradingInput {
        string marketLong;
        string marketShort;
        uint256 totalEthAmount;
        uint256 sizeDeltaUsdLong;
        uint256 sizeDeltaUsdShort;
        uint256 executionFee;
        uint256 slippageBps;
    }

    struct UsdcPairTradingInput {
        string marketLong;
        string marketShort;
        uint256 totalUsdcAmount;
        uint256 sizeDeltaUsdLong;
        uint256 sizeDeltaUsdShort;
        uint256 executionFee;
        uint256 slippageBps;
    }

    struct EtherOneSideTradeInput {
        uint256 ethAmount;
        uint256 sizeDeltaUsd;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 value;
        string market;
        bool isLong;
        address receiver;
    }

    struct UsdcOneSideTradeInput { // check
        uint256 usdcAmount;
        uint256 sizeDeltaUsd;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 value;
        string market;
        bool isLong;
        address receiver;
    }

    struct ClosePairTradingInput {
        uint256 positionId;
        uint256 executionFee;
        uint256 slippageBps;
    }

    struct CloseSidePairTradingInput {
        uint256 positionId;
        uint256 executionFee;
        uint256 slippageBps;
        uint256 value;
        bool isLongSide;
    }

    struct CloseSidePairTradingInputWithStopLoss {
        uint256 positionId;
        uint256 executionFee;
        uint256 slippageBps;
        uint256 value;
        uint256 triggerPrice;
        bool isLongSide;
    }

    struct RawExecutionData {
        uint256 positionId;
        address receiver;
        address outputToken;
        uint256 outputAmount;
        int256 pnl;
        uint256 executionPrice;
        uint256 collateralTokenPrice;
        bool isLongSide;
        bool processed;
        uint256 timestamp;
    }

    struct PendingOrder {
        address receiver;
        address proxy;
        uint256 positionId;
        bool isActive;
    }

}