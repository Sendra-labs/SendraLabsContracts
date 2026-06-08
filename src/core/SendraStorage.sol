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
    ///      Current highest index is 19 (totalLosingCapitalIn), so count = 20.
    uint8 internal constant GLOBAL_ACC_FIELD_COUNT = 20;

    /// @dev Numeric fields of SendraLib.SpecificAccumulators only; bytes metrics use updateSpecificPulseMetric.
    ///      Current highest index is 5 (totalPositions), so count = 6.
    uint8 internal constant SPECIFIC_ACC_FIELD_COUNT = 6;

    error InvalidGlobalAccumulatorField();
    error InvalidSpecificAccumulatorField();
    error AccumulatorBatchLengthMismatch();
    error InvalidSpecificMetricIndex();
    error InvalidSpecificMetricEncoding();
    error InvalidPositionRange();

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
     * @dev Field indices: 0 totalCapitalIn, 1 totalCapitalOut, 2 peakSimultaneousExposure, 3 currentExposure,
     *      4 cumulativeRealizedPnl, 5 grossProfit, 6 grossLoss, 7 highWaterMark, 8 maxDrawdown, 9 totalPositionsOpened,
     *      10 totalPositionsClosed, 11 winCount, 12 lossCount, 13 totalDurationSeconds, 14 firstActivityTimestamp,
     *      15 lastActivityTimestamp, 16 totalLiquidationEvents, 17 consecutiveLosses, 18 maxConsecutiveLosses,
     *      19 totalLosingCapitalIn.
     *      For uint256 fields the delta is added; subtraction saturates at 0 if the result would be negative.
     */
    function applyGlobalPulseDeltas(address _user, uint8[] calldata _fieldIds, int256[] calldata _deltas)
        public
        onlyProtocol
    {
        if (_fieldIds.length != _deltas.length) revert AccumulatorBatchLengthMismatch();
        if (!isUser(_user)) createUser(_user);
        SendraLib.GlobalAccumulators storage g = users[_user].pulse.globalPulse;

        if(g.firstActivityTimestamp == 0) {
            g.firstActivityTimestamp = block.timestamp;
        }

        for (uint256 i = 0; i < _fieldIds.length; i++) {
            uint8 f = _fieldIds[i];
            if (f >= GLOBAL_ACC_FIELD_COUNT) revert InvalidGlobalAccumulatorField();
            int256 d = _deltas[i];

            if (f == 0) {
                g.totalCapitalIn = _addUint256(g.totalCapitalIn, d);
            } else if (f == 1) {
                g.totalCapitalOut = _addUint256(g.totalCapitalOut, d);
            } else if (f == 2) {
                g.peakSimultaneousExposure = _addUint256(g.peakSimultaneousExposure, d);
            } else if (f == 3) {
                g.currentExposure = _addUint256(g.currentExposure, d);
            } else if (f == 4) {
                g.cumulativeRealizedPnl += d;
            } else if (f == 5) {
                g.grossProfit = _addUint256(g.grossProfit, d);
            } else if (f == 6) {
                g.grossLoss = _addUint256(g.grossLoss, d);
            } else if (f == 7) {
                g.highWaterMark += d;
            } else if (f == 8) {
                g.maxDrawdown = _addUint256(g.maxDrawdown, d);
            } else if (f == 9) {
                g.totalPositionsOpened = _addUint256(g.totalPositionsOpened, d);
            } else if (f == 10) {
                g.totalPositionsClosed = _addUint256(g.totalPositionsClosed, d);
            } else if (f == 11) {
                g.winCount = _addUint256(g.winCount, d);
            } else if (f == 12) {
                g.lossCount = _addUint256(g.lossCount, d);
            } else if (f == 13) {
                g.totalDurationSeconds = _addUint256(g.totalDurationSeconds, d);
            } else if (f == 14) {
                g.firstActivityTimestamp = _addUint256(g.firstActivityTimestamp, d);
            } else if (f == 15) {
                g.lastActivityTimestamp = _addUint256(g.lastActivityTimestamp, d);
            } else if (f == 16) {
                g.totalLiquidationEvents = _addUint256(g.totalLiquidationEvents, d);
            } else if (f == 17) {
                g.consecutiveLosses = _addUint256(g.consecutiveLosses, d);
            } else if (f == 18) {
                g.maxConsecutiveLosses = _addUint256(g.maxConsecutiveLosses, d);
            } else if (f == 19) {
                g.totalLosingCapitalIn = _addUint256(g.totalLosingCapitalIn, d);
            }
        }
    }

    /**
     * @notice Same batch pattern as applyGlobalPulseDeltas for SendraLib.SpecificAccumulators under a uint64 key (e.g. position type).
     * @dev Field indices: 0 realizedPnl, 1 totalCapitalIn, 2 totalCapitalOut, 3 winCount, 4 lossCount, 5 totalPositions.
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
                s.totalCapitalIn = _addUint256(s.totalCapitalIn, d);
            } else if (f == 2) {
                s.totalCapitalOut = _addUint256(s.totalCapitalOut, d);
            } else if (f == 3) {
                s.winCount = _addUint256(s.winCount, d);
            } else if (f == 4) {
                s.lossCount = _addUint256(s.lossCount, d);
            } else {
                s.totalPositions = _addUint256(s.totalPositions, d);
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

    /**
     * @notice Applies an int256 delta to a `uint256` metric stored in `specificMetrics[_metricIndex]`.
     * @dev Metric is expected to be `abi.encode(uint256)` when present. Empty bytes are treated as zero.
     *      Subtractions saturate at 0.
     */
    function applyMetricDelta(address _user, uint64 _specificKey, uint256 _metricIndex, int256 _delta)
        public
        onlyProtocol
    {
        if (!isUser(_user)) createUser(_user);
        SendraLib.SpecificAccumulators storage s = users[_user].pulse.specificPulse[_specificKey];

        uint256 current = 0;
        if (_metricIndex < s.specificMetrics.length) {
            bytes memory v = s.specificMetrics[_metricIndex];
            if (v.length == 0) {
                current = 0;
            } else if (v.length == 32) {
                current = abi.decode(v, (uint256));
            } else {
                revert InvalidSpecificMetricEncoding();
            }
        }

        uint256 next = _addUint256(current, _delta);

        if (_metricIndex >= s.specificMetrics.length) {
            s.specificMetrics.push(abi.encode(next));
        } else {
            s.specificMetrics[_metricIndex] = abi.encode(next);
        }
    }

    /**
     * @notice Applies an int256 delta to an `int256` metric stored in `specificMetrics[_metricIndex]`.
     * @dev Metric is expected to be `abi.encode(int256)` when present. Empty bytes are treated as zero.
     */
    function applyMetricDeltaSigned(address _user, uint64 _specificKey, uint256 _metricIndex, int256 _delta)
        public
        onlyProtocol
    {
        if (!isUser(_user)) createUser(_user);
        SendraLib.SpecificAccumulators storage s = users[_user].pulse.specificPulse[_specificKey];

        int256 current = 0;
        if (_metricIndex < s.specificMetrics.length) {
            bytes memory v = s.specificMetrics[_metricIndex];
            if (v.length == 0) {
                current = 0;
            } else if (v.length == 32) {
                current = abi.decode(v, (int256));
            } else {
                revert InvalidSpecificMetricEncoding();
            }
        }

        int256 next = current + _delta;

        if (_metricIndex >= s.specificMetrics.length) {
            s.specificMetrics.push(abi.encode(next));
        } else {
            s.specificMetrics[_metricIndex] = abi.encode(next);
        }
    }

    function _addUint256(uint256 _current, int256 _delta) private pure returns (uint256) {
        if (_delta >= 0) {
            return _current + uint256(_delta);
        } else {
            uint256 sub = uint256(-_delta);
            return _current >= sub ? (_current - sub) : 0;
        }
    }

    //____________

    /**
     * @notice Returns the user's global pulse accumulators.
     * @dev This is a convenience getter for `users[_user].pulse.globalPulse`.
     *      If the user has not been created yet, all fields will be zeroed.
     * @param _user The user address.
     */
    function getUserGlobalAccumulators(address _user) public view returns (SendraLib.GlobalAccumulators memory) {
        return users[_user].pulse.globalPulse;
    }

    /**
     * @notice Returns a single global accumulator for a given user and field id.
     * @dev Reverts if `_fieldId` is out of bounds for `globalPulse`.
     * @param _user The user address.
     * @param _fieldId The field id.
     */
    function getUniqueGlobalAccumulator(uint8 _fieldId, address _user) public view returns (int256) {
        int256 value = 0;
        if (_fieldId == 0) {
            value = int256(users[_user].pulse.globalPulse.totalCapitalIn);
        } else if (_fieldId == 1) {
            value = int256(users[_user].pulse.globalPulse.totalCapitalOut);
        } else if (_fieldId == 2) {
            value = int256(users[_user].pulse.globalPulse.peakSimultaneousExposure);
        } else if (_fieldId == 3) {
            value = int256(users[_user].pulse.globalPulse.currentExposure);
        } else if (_fieldId == 4) {
            value = users[_user].pulse.globalPulse.cumulativeRealizedPnl;
        } else if (_fieldId == 5) {
            value = int256(users[_user].pulse.globalPulse.grossProfit);
        } else if (_fieldId == 6) {
            value = int256(users[_user].pulse.globalPulse.grossLoss);
        } else if (_fieldId == 7) {
            value = users[_user].pulse.globalPulse.highWaterMark;
        } else if (_fieldId == 8) {
            value = int256(users[_user].pulse.globalPulse.maxDrawdown);
        } else if (_fieldId == 9) {
            value = int256(users[_user].pulse.globalPulse.totalPositionsOpened);
        } else if (_fieldId == 10) {
            value = int256(users[_user].pulse.globalPulse.totalPositionsClosed);
        } else if (_fieldId == 11) {
            value = int256(users[_user].pulse.globalPulse.winCount);
        } else if (_fieldId == 12) {
            value = int256(users[_user].pulse.globalPulse.lossCount);
        } else if (_fieldId == 13) {
            value = int256(users[_user].pulse.globalPulse.totalDurationSeconds);
        } else if (_fieldId == 14) {
            value = int256(users[_user].pulse.globalPulse.firstActivityTimestamp);
        } else if (_fieldId == 15) {
            value = int256(users[_user].pulse.globalPulse.lastActivityTimestamp);
        } else if (_fieldId == 16) {
            value = int256(users[_user].pulse.globalPulse.totalLiquidationEvents);
        } else if (_fieldId == 17) {
            value = int256(users[_user].pulse.globalPulse.consecutiveLosses);
        } else if (_fieldId == 18) {
            value = int256(users[_user].pulse.globalPulse.maxConsecutiveLosses);
        } else if (_fieldId == 19) {
            value = int256(users[_user].pulse.globalPulse.totalLosingCapitalIn);
        }
        return value;
    }

    /**
     * @notice Returns the user's specific pulse accumulators for a given key.
     * @dev Convenience getter for `users[_user].pulse.specificPulse[_specificKey]`.
     *      If the user/key has never been used, all fields will be zeroed and metrics length will be 0.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key (e.g. position type or strategy id).
     */
    function getUserSpecificAccumulators(address _user, uint64 _specificKey)
        public
        view
        returns (SendraLib.SpecificAccumulators memory)
    {
        return users[_user].pulse.specificPulse[_specificKey];
    }

    /**
     * @notice Returns a single specific metric blob for a given user and key.
     * @dev Reverts if `_metricIndex` is out of bounds for `specificMetrics`.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key.
     * @param _metricIndex The index within `specificMetrics`.
     */
    function getUserSpecificMetric(address _user, uint64 _specificKey, uint256 _metricIndex)
        public
        view
        returns (bytes memory)
    {
        SendraLib.SpecificAccumulators storage s = users[_user].pulse.specificPulse[_specificKey];
        if (_metricIndex >= s.specificMetrics.length) revert InvalidSpecificMetricIndex();
        return s.specificMetrics[_metricIndex];
    }

    /**
     * @notice Returns the number of metric blobs stored for a given user and key.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key.
     */
    function getUserSpecificMetricsLength(address _user, uint64 _specificKey) public view returns (uint256) {
        return users[_user].pulse.specificPulse[_specificKey].specificMetrics.length;
    }

    function getUserPositionById(address _user, uint256 _positionId) public view returns (SendraLib.Position memory position) {
        position = users[_user].globalPosition.positions[_positionId];
        return position;
    }

    /**
     * @notice Returns positions for a user in the inclusive ID range [_fromId, _toId].
     * @dev Position IDs are 1-indexed up to `globalPosition.totalPositions`.
     */
    function getUserPositionsByRange(address _user, uint256 _fromId, uint256 _toId)
        public
        view
        returns (SendraLib.Position[] memory positions)
    {
        if (_fromId == 0 || _fromId > _toId || _toId > users[_user].globalPosition.totalPositions) {
            revert InvalidPositionRange();
        }

        positions = new SendraLib.Position[](_toId - _fromId + 1);
        for (uint256 i = _fromId; i <= _toId; i++) {
            positions[i - _fromId] = users[_user].globalPosition.positions[i];
        }
    }

    /**
     * @notice Returns positions for a user matching each ID in `_positionIds` (same order).
     */
    function getUserPositionsByIds(address _user, uint256[] calldata _positionIds)
        public
        view
        returns (SendraLib.Position[] memory positions)
    {
        positions = new SendraLib.Position[](_positionIds.length);
        for (uint256 i = 0; i < _positionIds.length; i++) {
            positions[i] = users[_user].globalPosition.positions[_positionIds[i]];
        }
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
