//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ProtocolLib {
    
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
        Position[] positions; // Only active positions ??
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