//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ProtocolLib {
    
    // 0 = uint; 1 = address; 2 = bool; 3 = bytes; 4 = uint256[]; 5 = address[]; 6 = bool[]; 7 = bytes[]; 8 = uint256[][]; 9 = address[][]; 10 = bool[][]; 11 = bytes[][]; 12 = uint256[][][]; 13 = address[][][]; 14 = bool[][][]; 
   struct PositionParam {
        uint8 paramType;
        string paramName;
    }
    
    // origins se refiere a 0 = Funds o 1 = Bundles
    struct PositionType {
        string name;
        uint8 origin;
        PositionParam[] positionParams; 
    }

    // positionType is the ID of the position type
    // positionType must be the same as positionsTypes mapping at UpgradeableLib
    struct Position {
        uint128 positionType;
        int256 pnl;
        bytes[] positionData;
    }

    struct GlobalPosition {
        uint256 totalPositions; // closed and active
        uint256 activePositions; 
        Position[] positions; // Only active positions
    }

    struct UserDataField {
        string fieldName;
        uint8 fieldType;
    }

    struct User {
        uint256 id;
        int256 globalPnl;
        GlobalPosition globalPosition;
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