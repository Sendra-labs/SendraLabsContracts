/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                    
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒        SENDRA STORAGE                                                                                                                                  
________________________________________________________________
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SendraLib } from "../lib/Sendra.lib.sol";
import { Roles } from "../security/Roles.sol";

/**
 * @title SendraStorage
 * @author @Diego-AVZ
 * @notice Centralized storage for SendraPulse and per-user accumulators (SendraLib.User).
 * @dev Same baseline surface as ProtocolStorage; writes only through onlyProtocol.
 */
contract SendraStorage {

    Roles public roles;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier onlyProtocol() {
        if (!roles.isProtocolContract(msg.sender)) revert InvalidProtocol();
        _;
    }

    error InvalidProtocol();

    SendraLib.ProtocolStats internal protocolStats;

    mapping(address => SendraLib.User) internal users;

    mapping(uint256 => address) public usersById;

    /// @dev Indices match the declaration order of fields in SendraLib.GlobalAccumulators (Sendra.lib.sol).
    uint8 internal constant GLOBAL_ACC_FIELD_COUNT = 18;

    /// @dev Numeric fields of SendraLib.SpecificAccumulators only; bytes metrics use updateSpecificPulseMetric.
    uint8 internal constant SPECIFIC_ACC_FIELD_COUNT = 5;

    error InvalidGlobalAccumulatorField();
    error InvalidSpecificAccumulatorField();
    error AccumulatorBatchLengthMismatch();

    function createUser(address _user) internal onlyProtocol {
        protocolStats.totalUsers++;
        SendraLib.User storage newUser = users[_user];
        newUser.id = protocolStats.totalUsers;
        newUser.globalPnl = 0;
        newUser.globalPosition.totalPositions = 0;
        newUser.globalPosition.activePositions = 0;
        newUser.transactionCount = 0;
        usersById[protocolStats.totalUsers] = _user;
    }

    function getUser(address _user) public view returns (SendraLib.UserInfoRead memory) {
        SendraLib.User storage user = users[_user];

        return SendraLib.UserInfoRead(
            user.id,
            user.globalPnl,
            user.globalPosition.totalPositions,
            user.globalPosition.activePositions,
            user.transactionCount,
            user.userData
        );
    }

    function updateUserTransactionCount(address _user, uint256 _transactionCount) public onlyProtocol {
        if (!isUser(_user)) createUser(_user);
        SendraLib.User storage user = users[_user];
        user.transactionCount += _transactionCount;
    }

    function finalizePosition(uint256 _positionId, address _user) external onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].isActive = false;
        user.globalPosition.activePositions--;
    }

    function addPositionToUser(address _user, SendraLib.Position memory _position) public onlyProtocol {
        if (!isUser(_user)) createUser(_user);
        SendraLib.User storage user = users[_user];
        user.transactionCount++;
        user.globalPosition.totalPositions++;
        user.globalPosition.activePositions++;
        user.globalPosition.positions[user.globalPosition.totalPositions] = _position;
    }

    function updateUserFullPosition(address _user, uint256 _positionId, SendraLib.Position memory _position) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId] = _position;
    }

    function updateUserPositionData(address _user, uint256 _positionId, uint256 _positionField, bytes memory _value) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        if (_positionField >= user.globalPosition.positions[_positionId].positionData.length) {
            user.globalPosition.positions[_positionId].positionData.push(_value);
        } else {
            user.globalPosition.positions[_positionId].positionData[_positionField] = _value;
        }
    }

    function updateUserPositionPnl(address _user, uint256 _positionId, int256 _pnlChange) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].pnl += _pnlChange;
    }

    function updateUserPositionIsActive(address _user, uint256 _positionId, bool _isActive) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].isActive = _isActive;
    }

    function updateUserGlobalPnl(address _user, int256 _pnlChange) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPnl += _pnlChange;
    }

    function addUserData(SendraLib.User storage _user, bytes memory _data) internal {
        _user.userData.push(_data);
    }

    function updateUserData(address _user, uint256 _dataIndex, bytes memory _data) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        if (_dataIndex >= user.userData.length) {
            addUserData(user, _data);
        } else {
            user.userData[_dataIndex] = _data;
        }
    }

    function decreaseGlobalPositionActivePositions(address _user) public onlyProtocol {
        SendraLib.User storage user = users[_user];
        user.globalPosition.activePositions--;
    }

    //____________

    //STORAGE V2

    /**
     * @notice Applies int256 deltas to each GlobalAccumulators field selected by index.
     * @dev Field indices: 0 totalCapitalIn, 1 totalCapitalOut, 2 peakSimultaneousExposure, 3 cumulativeRealizedPnl,
     *      4 grossProfit, 5 grossLoss, 6 highWaterMark, 7 maxDrawdown, 8 totalPositionsOpened, 9 totalPositionsClosed,
     *      10 winCount, 11 lossCount, 12 totalDurationSeconds, 13 firstActivityTimestamp, 14 lastActivityTimestamp,
     *      15 totalLiquidationEvents, 16 consecutiveLosses, 17 maxConsecutiveLosses.
     *      For uint256 fields the delta is added; subtraction saturates at 0 if the result would be negative.
     */
    function applyGlobalPulseDeltas(address _user, uint8[] calldata _fieldIds, int256[] calldata _deltas)
        public
        onlyProtocol
    {
        if (_fieldIds.length != _deltas.length) revert AccumulatorBatchLengthMismatch();
        if (!isUser(_user)) createUser(_user);
        SendraLib.GlobalAccumulators storage g = users[_user].pulse.globalPulse;

        for (uint256 i = 0; i < _fieldIds.length; i++) {
            uint8 f = _fieldIds[i];
            if (f >= GLOBAL_ACC_FIELD_COUNT) revert InvalidGlobalAccumulatorField();
            int256 d = _deltas[i];

            if (f == 0) {
                _addUint256(g.totalCapitalIn, d);
            } else if (f == 1) {
                _addUint256(g.totalCapitalOut, d);
            } else if (f == 2) {
                _addUint256(g.peakSimultaneousExposure, d);
            } else if (f == 3) {
                g.cumulativeRealizedPnl += d;
            } else if (f == 4) {
                _addUint256(g.grossProfit, d);
            } else if (f == 5) {
                _addUint256(g.grossLoss, d);
            } else if (f == 6) {
                g.highWaterMark += d;
            } else if (f == 7) {
                _addUint256(g.maxDrawdown, d);
            } else if (f == 8) {
                _addUint256(g.totalPositionsOpened, d);
            } else if (f == 9) {
                _addUint256(g.totalPositionsClosed, d);
            } else if (f == 10) {
                _addUint256(g.winCount, d);
            } else if (f == 11) {
                _addUint256(g.lossCount, d);
            } else if (f == 12) {
                _addUint256(g.totalDurationSeconds, d);
            } else if (f == 13) {
                _addUint256(g.firstActivityTimestamp, d);
            } else if (f == 14) {
                _addUint256(g.lastActivityTimestamp, d);
            } else if (f == 15) {
                _addUint256(g.totalLiquidationEvents, d);
            } else if (f == 16) {
                _addUint256(g.consecutiveLosses, d);
            } else {
                _addUint256(g.maxConsecutiveLosses, d);
            }
        }
    }

    /**
     * @notice Same batch pattern as applyGlobalPulseDeltas for SendraLib.SpecificAccumulators under a uint64 key (e.g. position type).
     * @dev Field indices: 0 realizedPnl, 1 capitalDeployed, 2 winCount, 3 lossCount, 4 totalPositions.
     */
    function applySpecificPulseDeltas(address _user, uint64 _specificKey, uint8[] calldata _fieldIds, int256[] calldata _deltas)
        public
        onlyProtocol
    {
        if (_fieldIds.length != _deltas.length) revert AccumulatorBatchLengthMismatch();
        if (!isUser(_user)) createUser(_user);
        SendraLib.SpecificAccumulators storage s = users[_user].pulse.specificPulse[_specificKey];

        for (uint256 i = 0; i < _fieldIds.length; i++) {
            uint8 f = _fieldIds[i];
            if (f >= SPECIFIC_ACC_FIELD_COUNT) revert InvalidSpecificAccumulatorField();
            int256 d = _deltas[i];

            if (f == 0) {
                s.realizedPnl += d;
            } else if (f == 1) {
                _addUint256(s.capitalDeployed, d);
            } else if (f == 2) {
                _addUint256(s.winCount, d);
            } else if (f == 3) {
                _addUint256(s.lossCount, d);
            } else {
                _addUint256(s.totalPositions, d);
            }
        }
    }

    /**
     * @notice Updates or appends specificMetrics[_metricIndex] using the same rules as updateUserPositionData for positionData.
     */
    function updateSpecificPulseMetric(address _user, uint64 _specificKey, uint256 _metricIndex, bytes memory _value)
        public
        onlyProtocol
    {
        if (!isUser(_user)) createUser(_user);
        SendraLib.SpecificAccumulators storage s = users[_user].pulse.specificPulse[_specificKey];
        if (_metricIndex >= s.specificMetrics.length) {
            s.specificMetrics.push(_value);
        } else {
            s.specificMetrics[_metricIndex] = _value;
        }
    }

    function _addUint256(uint256 storage _slot, int256 _delta) private {
        if (_delta >= 0) {
            _slot += uint256(_delta);
        } else {
            uint256 sub = uint256(-_delta);
            if (_slot >= sub) {
                _slot -= sub;
            } else {
                _slot = 0;
            }
        }
    }

    //____________

    function getUserPositionById(address _user, uint256 _positionId) public view returns (SendraLib.Position memory position) {
        position = users[_user].globalPosition.positions[_positionId];
        return position;
    }

    function isUser(address _user) public view returns (bool) {
        return users[_user].id != 0;
    }

    function getUsersCount() public view returns (uint256) {
        return protocolStats.totalUsers;
    }

    function getProtocolStats() public view returns (SendraLib.ProtocolStats memory) {
        return protocolStats;
    }

    function getUserAddressById(uint256 _id) public view returns (address) {
        return usersById[_id];
    }

    function getUserIdByAddress(address _user) public view returns (uint256) {
        return users[_user].id;
    }

    function getUserDataById(uint256 _id) public view returns (SendraLib.UserInfoRead memory, address) {
        return (getUser(usersById[_id]), usersById[_id]);
    }

    function updateTotalVolume(uint256 _amount) public onlyProtocol {
        protocolStats.totalVolume += _amount;
    }

    function updateTotalPnl(int256 _pnl) public onlyProtocol {
        protocolStats.totalPnl += _pnl;
    }

    function updateTotalTransactions() public onlyProtocol {
        protocolStats.totalTransactions++;
    }

    function updateTotalPositions() public onlyProtocol {
        protocolStats.totalPositions++;
    }

    function updateTotalActivePositions(int256 _change) public onlyProtocol {
        if (_change > 0) {
            protocolStats.totalActivePositions += uint256(_change);
        } else {
            uint256 decrease = uint256(-_change);
            if (protocolStats.totalActivePositions >= decrease) {
                protocolStats.totalActivePositions -= decrease;
            } else {
                protocolStats.totalActivePositions = 0;
            }
        }
    }

    function updateTotalValueLocked(int256 _change) public onlyProtocol {
        if (_change > 0) {
            protocolStats.totalValueLocked += uint256(_change);
        } else {
            uint256 decrease = uint256(-_change);
            if (protocolStats.totalValueLocked >= decrease) {
                protocolStats.totalValueLocked -= decrease;
            } else {
                protocolStats.totalValueLocked = 0;
            }
        }
    }

}
