//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Price } from "../price/Price.sol";

/**
 * @title PositionPricingUtils
 * @notice Position pricing utilities for GMX
 * @dev Simplified version for interface compatibility
 */
library PositionPricingUtils {
    
    struct PositionFees {
        PositionReferralFees referral;
        PositionProFees pro;
        PositionFundingFees funding;
        PositionBorrowingFees borrowing;
        PositionUiFees ui;
        PositionLiquidationFees liquidation;
        Price.Props collateralTokenPrice;
        uint256 positionFeeAmount;
        uint256 borrowingFeeAmount;
        uint256 fundingFeeAmount;
        uint256 totalCostAmountExcludingFunding;
        uint256 totalCostAmount;
        uint256 totalDiscountAmount;
    }
    
    struct PositionReferralFees {
        uint256 totalRebateFactor;
        uint256 totalRebateAmount;
        uint256 totalReferralAmount;
    }
    
    struct PositionProFees {
        uint256 totalRebateFactor;
        uint256 totalRebateAmount;
        uint256 totalReferralAmount;
    }
    
    struct PositionFundingFees {
        uint256 fundingFeeAmount;
        uint256 claimableLongTokenAmount;
        uint256 claimableShortTokenAmount;
        uint256 latestFundingFeeAmountPerSize;
        uint256 latestLongTokenClaimableFundingAmountPerSize;
        uint256 latestShortTokenClaimableFundingAmountPerSize;
    }
    
    struct PositionBorrowingFees {
        uint256 borrowingFeeUsd;
        uint256 borrowingFeeAmount;
        uint256 borrowingFeeReceiverFactor;
        uint256 borrowingFeeAmountForFeeReceiver;
    }
    
    struct PositionUiFees {
        uint256 uiFeeAmount;
    }
    
    struct PositionLiquidationFees {
        uint256 liquidationFeeAmount;
    }
}
