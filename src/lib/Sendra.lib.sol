//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SendraLib {
    
    // 0 = uint; 1 = address; 2 = bool; 3 = bytes; 4 = uint256[]; 5 = address[]; 6 = bool[]; 7 = bytes[]; 8 = uint256[][]; 9 = address[][]; 10 = bool[][]; 11 = bytes[][]; 12 = uint256[][][]; 13 = address[][][]; 14 = bool[][][]; 
   struct PositionParam {
        uint8 paramType;
        string paramName;
    }
    
    struct FunctionInputs {
        uint8 inputType;
        string inputName;
    }

    // origins se refiere a 0 = Funds o 1 = Bundles
    struct PositionType {
        string name;
        uint8 origin;
        PositionParam[] positionParams;
        FunctionInputs[] openPositionInputs;
        FunctionInputs[] closePositionInputs;
    }
    // _________________________________________________

    // positionType is the ID of the position type
    // positionType must be the same as positionsTypes mapping at UpgradeableLib
    struct Position {
        uint128 positionType;
        uint256 id;
        int256 pnl;
        bool isActive;
        bytes[] positionData;
    }

    struct GlobalPosition {
        uint256 totalPositions; // closed and active // used to get the positionId
        uint256 activePositions; 
        mapping(uint256 => Position) positions;
    }

    struct UserDataField {
        string fieldName;
        uint8 fieldType;
    }

    struct User {
        uint256 id;
        int256 globalPnl;
        GlobalPosition globalPosition;
        // i think transactionCount it is the same as totalPositions 
        uint256 transactionCount; // will be used as positionId for each user also
        bytes[] userData;
        SendraPulse pulse;
    }

    struct SendraPulse {
        GlobalAccumulators globalPulse;
        mapping(uint64 => SpecificAccumulators) specificPulse;
    }

    struct GlobalAccumulators {
        // CAPITAL
        /// @notice Total capital deposited across all positions, ever.
        /// @dev Denominated in the base accounting unit (e.g. USDC with 6 decimals).
        uint256 totalCapitalIn; // 0
        /// @notice Total capital withdrawn across all closed positions, including PnL.
        /// @dev ROI = (totalCapitalOut - totalCapitalIn) / totalCapitalIn
        uint256 totalCapitalOut; // 1
        /// @notice Highest simultaneous capital at risk ever recorded across open positions.
        /// @dev Updated on position open if current total exposure exceeds the stored peak.
        ///      Useful for Rulers enforcing real leverage limits without iterating open positions.
        uint256 peakSimultaneousExposure; // 2

        uint256 currentExposure; // 3
        
        // PNL
        /// @notice Sum of realized PnL across all closed positions. Can be negative.
        /// @dev Updated at every position close: cumulativeRealizedPnl += closeValue - openValue
        int256 cumulativeRealizedPnl; // 4
        /// @notice Sum of PnL from winning positions only (PnL > 0).
        /// @dev Combined with grossLoss allows Rulers to compute profitFactor = grossProfit / grossLoss
        ///      without any historical iteration.
        uint256 grossProfit; // 5
        /// @notice Sum of absolute PnL from losing positions only (PnL < 0), stored as positive.
        /// @dev profitFactor = grossProfit / grossLoss. A value above 1.0 means the user is net profitable
        ///      even with a sub-50% win rate.
        uint256 grossLoss; // 6
        /// @notice Highest value ever reached by cumulativeRealizedPnl. Always >= 0.
        /// @dev Updated at every position close if cumulativeRealizedPnl > highWaterMark.
        ///      Used as the reference point to compute current and maximum drawdown.
        int256 highWaterMark; // 7
        /// @notice Largest drop from highWaterMark ever recorded, stored as a positive magnitude.
        /// @dev Updated at every position close: if (highWaterMark - cumulativeRealizedPnl) > maxDrawdown.
        ///      Critical for prop-firm style Rulers that hard-stop access above a drawdown threshold.
        uint256 maxDrawdown; // 8

        // ACTIVITY
        /// @notice Total number of positions opened, including currently active ones.
        /// @dev Incremented on open. Used as a proxy for overall protocol engagement.
        uint256 totalPositionsOpened; // 9
        /// @notice Total number of positions fully closed.
        /// @dev Denominator for winRate, avgHoldingTime, and other per-position averages.
        uint256 totalPositionsClosed; // 10
        /// @notice Number of closed positions with a positive realized PnL.
        /// @dev winRate = winCount / totalPositionsClosed
        uint256 winCount; // 11
        /// @notice Number of closed positions with a negative or zero realized PnL.
        /// @dev lossRate = lossCount / totalPositionsClosed
        uint256 lossCount; // 12                    
        /// @notice Cumulative duration in seconds of all closed positions.
        /// @dev avgHoldingTime = totalDurationSeconds / totalPositionsClosed
        ///      Computed as: block.timestamp (at close) - openTimestamp (stored on Position).
        uint256 totalDurationSeconds; // 13

        // TIME
        /// @notice Timestamp of the user's first ever position open on Sendra.
        /// @dev Set once on first interaction. Never updated after initialization.
        ///      Seniority proxy: lastActivityTimestamp - firstActivityTimestamp.
        uint256 firstActivityTimestamp; // 14
        /// @notice Timestamp of the most recent closed position.
        /// @dev Updated at every position close. Rulers can use this to detect inactive users
        ///      or enforce minimum activity windows for capital access.
        uint256 lastActivityTimestamp; // 15

        // RISK
        /// @notice Total number of liquidation events suffered across all positions.
        /// @dev A non-zero value is a strong negative reputation signal.
        ///      Rulers can hard-block access to undercollateralized products above a threshold.
        uint256 totalLiquidationEvents; // 16
        /// @notice Current consecutive loss streak (resets to 0 on any winning position).
        /// @dev Provides a fast, reactive risk signal. Rulers can trigger cooling-off periods
        ///      without waiting for drawdown to accumulate.
        uint256 consecutiveLosses; // 17
        /// @notice Longest consecutive loss streak ever recorded for this user.
        /// @dev Historical worst-case behavioral signal. Complements maxDrawdown
        ///      by capturing streaks rather than magnitude.
        uint256 maxConsecutiveLosses; // 18
    }

    struct SpecificAccumulators {
        int256 realizedPnl; // 0
        uint256 totalCapitalIn; // 1
        uint256 totalCapitalOut; // 2
        uint256 winCount; // 3
        uint256 lossCount; // 4
        uint256 totalPositions; // 5
        bytes[] specificMetrics;
    }

    struct UserInfoRead {
        uint256 id;
        int256 globalPnl;
        uint256 totalPositions;
        uint256 activePositions;
        uint256 transactionCount;
        bytes[] userData;
    }

    struct ProtocolStats {
        uint256 totalUsers;
        uint256 totalVolume;
        int256 totalPnl;
        uint256 totalTransactions;
        uint256 totalPositions;
        uint256 totalActivePositions;
        uint256 totalValueLocked;
    }

    struct Partner {
        address member;
        uint256 equity;
        uint256 etherRevenue;
        uint256 usdRevenue;
        uint256 equitySold;
    }

    struct DeFiParam {
        uint8 _type;
        bytes v;
        address w;
        uint256 x;
        int256 y;
        bool z;
    }

}