//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IReader
 * @notice Interface for GMX Reader contract
 * @dev This interface defines the functions to read position data from GMX
 */
interface IReader {
    
    // ========== STRUCTURES ==========
    
    struct Position {
        address account;
        address market;
        address collateralToken;
        uint256 sizeInUsd;
        uint256 sizeInTokens;
        uint256 collateralAmount;
        int256 pendingImpactAmount;
        uint256 borrowingFactor;
        uint256 fundingFeeAmountPerSize;
        uint256 longTokenClaimableFundingAmountPerSize;
        uint256 shortTokenClaimableFundingAmountPerSize;
        uint256 increasedAtTime;
        uint256 decreasedAtTime;
        bool isLong;
    }
    
    struct Price {
        uint256 min;
        uint256 max;
    }
    
    struct Market {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }
    
    struct MarketPrices {
        Price indexTokenPrice;
        Price longTokenPrice;
        Price shortTokenPrice;
    }
    
    struct PositionFees {
        uint256 positionFeeAmount;
        uint256 totalCostAmount;
        PositionBorrowingFees borrowing;
        PositionFundingFees funding;
        Price collateralTokenPrice;
    }
    
    struct PositionBorrowingFees {
        uint256 borrowingFeeUsd;
        uint256 borrowingFeeAmount;
    }
    
    struct PositionFundingFees {
        uint256 fundingFeeAmount;
        uint256 claimableLongTokenAmount;
        uint256 claimableShortTokenAmount;
    }
    
    struct PositionInfo {
        bytes32 positionKey;
        Position position;
        PositionFees fees;
        int256 basePnlUsd;
        int256 uncappedBasePnlUsd;
        int256 pnlAfterPriceImpactUsd;
    }
    
    // ========== FUNCTIONS ==========
    
    /**
     * @notice Gets basic position data from DataStore
     * @param dataStore Address of GMX DataStore contract
     * @param key Position key
     * @return position Position struct with basic data
     */
    function getPosition(
        address dataStore,
        bytes32 key
    ) external view returns (Position memory position);
    
    /**
     * @notice Gets complete position information with real-time calculations
     * @param dataStore Address of GMX DataStore contract
     * @param referralStorage Address of GMX ReferralStorage contract
     * @param positionKey Position key
     * @param prices Current market prices
     * @param sizeDeltaUsd Size delta in USD (0 for full position)
     * @param uiFeeReceiver Address for UI fees (address(0) for queries)
     * @param usePositionSizeAsSizeDeltaUsd true to use full position size
     * @return positionInfo Complete PositionInfo struct with PNL, fees, etc.
     */
    function getPositionInfo(
        address dataStore,
        address referralStorage,
        bytes32 positionKey,
        MarketPrices memory prices,
        uint256 sizeDeltaUsd,
        address uiFeeReceiver,
        bool usePositionSizeAsSizeDeltaUsd
    ) external view returns (PositionInfo memory positionInfo);
    
    /**
     * @notice Gets all positions for an account
     * @param dataStore Address of GMX DataStore contract
     * @param account Account address
     * @param start Start index
     * @param end End index
     * @return positions Array of Position structs
     */
    function getAccountPositions(
        address dataStore,
        address account,
        uint256 start,
        uint256 end
    ) external view returns (Position[] memory positions);
    
    /**
     * @notice Gets market information
     * @param dataStore Address of GMX DataStore contract
     * @param key Market address
     * @return market Market struct
     */
    function getMarket(
        address dataStore,
        address key
    ) external view returns (Market memory market);
    
    /**
     * @notice Gets PNL for a position
     * @param dataStore Address of GMX DataStore contract
     * @param market Market struct
     * @param prices Market prices
     * @param positionKey Position key
     * @param sizeDeltaUsd Size delta in USD
     * @return pnl PNL in USD
     * @return uncappedPnl Uncapped PNL
     * @return sizeDeltaInTokens Size delta in tokens
     */
    function getPositionPnlUsd(
        address dataStore,
        Market memory market,
        MarketPrices memory prices,
        bytes32 positionKey,
        uint256 sizeDeltaUsd
    ) external view returns (int256 pnl, int256 uncappedPnl, uint256 sizeDeltaInTokens);
}

