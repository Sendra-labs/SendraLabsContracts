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
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

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
    error NotAdmin();
    error InvalidSyncer();
    error StalePulseVersion(uint64 current, uint64 expected);
    error InvalidPulseVersion();
    error SealHashMismatch(bytes32 current, bytes32 expected);
    error InvalidLink();
    error LinkExpired();
    error InvalidLinkSignature();
    error AlreadyLinked();
    error LinkWalletLimit();

    /// @notice Authorized key that may seal and commit the global pulse. Replaceable by an admin.
    address public pulseSyncer;

    uint256 public constant MAX_LINKED_WALLETS = 16;

    /// @dev Zero means the wallet is its own accounting root.
    mapping(address => address) public walletRoot;
    mapping(address => address[]) internal linkedWallets;
    mapping(address => uint256) public linkNonce;
    mapping(address => SendraLib.PositionRef[]) internal accountingPositions;

    bytes32 private constant LINK_TYPEHASH = keccak256(
        "LinkWallets(address walletA,address walletB,uint256 nonceA,uint256 nonceB,uint256 deadline)"
    );
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    event PulseSyncerSet(address indexed syncer);
    event TemporalSealed(address indexed root, uint64 indexed baseVersion, bytes32 sealHash);
    event GlobalPulseCommitted(
        address indexed root,
        uint64 indexed version,
        bytes32 consumedSealHash,
        uint256[] chainIds,
        bytes32[] sealHashes
    );
    event WalletsLinked(address indexed root, address indexed joined, uint256 walletCount);

    modifier onlyPulseSyncer() {
        if (msg.sender != pulseSyncer) revert InvalidSyncer();
        _;
    }

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
        accountingPositions[accountingRootOf(_user)].push(
            SendraLib.PositionRef({ wallet: _user, positionId: user.globalPosition.totalPositions })
        );
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
     * @notice Applies int256 deltas for one user action.
     * @dev Summable fields land in the temporal pulse. Sequence metrics and timestamps stay on the
     *      global pulse of this chain because they must not be added together across networks.
     *      Field indices: 0 totalCapitalIn, 1 totalCapitalOut, 2 peakSimultaneousExposure, 3 currentExposure,
     *      4 cumulativeRealizedPnl, 5 grossProfit, 6 grossLoss, 7 highWaterMark, 8 maxDrawdown, 9 totalPositionsOpened,
     *      10 totalPositionsClosed, 11 winCount, 12 lossCount, 13 totalDurationSeconds, 14 firstActivityTimestamp,
     *      15 lastActivityTimestamp, 16 totalLiquidationEvents, 17 consecutiveLosses, 18 maxConsecutiveLosses,
     *      19 totalLosingCapitalIn.
     *      For uint256 fields the delta is added; subtraction saturates at 0 if the result would be negative.
     *      Linked wallets write the shared accounting root.
     */
    function applyGlobalPulseDeltas(address _user, uint8[] calldata _fieldIds, int256[] calldata _deltas)
        public
        onlyProtocol
    {
        if (_fieldIds.length != _deltas.length) revert AccumulatorBatchLengthMismatch();
        address root = _touchRoot(_user);
        SendraLib.SendraPulse storage pulse = users[root].pulse;

        if (pulse.globalPulse.firstActivityTimestamp == 0) {
            pulse.globalPulse.firstActivityTimestamp = block.timestamp;
        }

        for (uint256 i = 0; i < _fieldIds.length; i++) {
            uint8 f = _fieldIds[i];
            if (f >= GLOBAL_ACC_FIELD_COUNT) revert InvalidGlobalAccumulatorField();
            if (_isImmediate(f)) {
                _applyAccumulator(pulse.globalPulse, f, _deltas[i]);
            } else {
                _applyAccumulator(pulse.temporalPulse, f, _deltas[i]);
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
        address root = _touchRoot(_user);
        SendraLib.SpecificAccumulators storage s = users[root].pulse.specificPulse[_specificKey];

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
        address root = _touchRoot(_user);
        SendraLib.SpecificAccumulators storage s = users[root].pulse.specificPulse[_specificKey];
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
        address root = _touchRoot(_user);
        SendraLib.SpecificAccumulators storage s = users[root].pulse.specificPulse[_specificKey];

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
        address root = _touchRoot(_user);
        SendraLib.SpecificAccumulators storage s = users[root].pulse.specificPulse[_specificKey];

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

    /// @dev Sequence metrics and timestamps are chain-local. Everything else is a pending global delta.
    function _isImmediate(uint8 _fieldId) private pure returns (bool) {
        return _fieldId == 2 || _fieldId == 7 || _fieldId == 8 || _fieldId == 14 || _fieldId == 15
            || _fieldId == 17 || _fieldId == 18;
    }

    function _applyAccumulator(SendraLib.GlobalAccumulators storage g, uint8 f, int256 d) private {
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

    function _readField(SendraLib.GlobalAccumulators storage g, uint8 f) private view returns (int256) {
        if (f == 0) return int256(g.totalCapitalIn);
        if (f == 1) return int256(g.totalCapitalOut);
        if (f == 2) return int256(g.peakSimultaneousExposure);
        if (f == 3) return int256(g.currentExposure);
        if (f == 4) return g.cumulativeRealizedPnl;
        if (f == 5) return int256(g.grossProfit);
        if (f == 6) return int256(g.grossLoss);
        if (f == 7) return g.highWaterMark;
        if (f == 8) return int256(g.maxDrawdown);
        if (f == 9) return int256(g.totalPositionsOpened);
        if (f == 10) return int256(g.totalPositionsClosed);
        if (f == 11) return int256(g.winCount);
        if (f == 12) return int256(g.lossCount);
        if (f == 13) return int256(g.totalDurationSeconds);
        if (f == 14) return int256(g.firstActivityTimestamp);
        if (f == 15) return int256(g.lastActivityTimestamp);
        if (f == 16) return int256(g.totalLiquidationEvents);
        if (f == 17) return int256(g.consecutiveLosses);
        if (f == 18) return int256(g.maxConsecutiveLosses);
        return int256(g.totalLosingCapitalIn);
    }

    //____________

    /**
     * @notice Returns the consolidated global pulse, without temporal or sealed deltas.
     * @dev Live summable reputation for product code is `getUniqueGlobalAccumulator`, which adds the
     *      pending slices. Linked wallets resolve to the accounting root.
     */
    function getUserGlobalAccumulators(address _user) public view returns (SendraLib.GlobalAccumulators memory) {
        return users[accountingRootOf(_user)].pulse.globalPulse;
    }

    /**
     * @notice Returns one accumulator as the protocol executors should read it.
     * @dev Summable fields are global + temporal + sealed. Sequence metrics and timestamps are the
     *      chain-local global value. Reverts if `_fieldId` is out of range.
     */
    function getUniqueGlobalAccumulator(uint8 _fieldId, address _user) public view returns (int256) {
        if (_fieldId >= GLOBAL_ACC_FIELD_COUNT) revert InvalidGlobalAccumulatorField();
        SendraLib.SendraPulse storage pulse = users[accountingRootOf(_user)].pulse;
        if (_isImmediate(_fieldId)) return _readField(pulse.globalPulse, _fieldId);
        return _readField(pulse.globalPulse, _fieldId) + _readField(pulse.temporalPulse, _fieldId)
            + _readField(pulse.sealedPulse, _fieldId);
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
        return users[accountingRootOf(_user)].pulse.specificPulse[_specificKey];
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
        SendraLib.SpecificAccumulators storage s = users[accountingRootOf(_user)].pulse.specificPulse[_specificKey];
        if (_metricIndex >= s.specificMetrics.length) revert InvalidSpecificMetricIndex();
        return s.specificMetrics[_metricIndex];
    }

    /**
     * @notice Returns the number of metric blobs stored for a given user and key.
     * @param _user The user address.
     * @param _specificKey The specific accumulator key.
     */
    function getUserSpecificMetricsLength(address _user, uint64 _specificKey) public view returns (uint256) {
        return users[accountingRootOf(_user)].pulse.specificPulse[_specificKey].specificMetrics.length;
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
        address root = accountingRootOf(_user);
        if (users[root].id != 0) return users[root].id;
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

    //____________

    // MULTICHAIN PULSE

    function setPulseSyncer(address _syncer) external {
        if (!roles.checkAdmin(msg.sender)) revert NotAdmin();
        if (_syncer == address(0)) revert InvalidSyncer();
        pulseSyncer = _syncer;
        emit PulseSyncerSet(_syncer);
    }

    /// @notice Accounting root for a wallet. An unlinked wallet is its own root.
    function accountingRootOf(address _wallet) public view returns (address) {
        address root = walletRoot[_wallet];
        return root == address(0) ? _wallet : root;
    }

    function getAccountingWallets(address _wallet) public view returns (address[] memory wallets) {
        address root = accountingRootOf(_wallet);
        uint256 n = linkedWallets[root].length;
        if (n == 0) {
            wallets = new address[](1);
            wallets[0] = root;
            return wallets;
        }
        wallets = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            wallets[i] = linkedWallets[root][i];
        }
    }

    function getAccountingOverview(address _wallet) public view returns (SendraLib.AccountingOverview memory overview) {
        address root = accountingRootOf(_wallet);
        address[] memory wallets = getAccountingWallets(_wallet);
        overview.root = root;
        overview.userId = users[root].id != 0 ? users[root].id : users[_wallet].id;
        overview.walletCount = wallets.length;
        for (uint256 i = 0; i < wallets.length; i++) {
            SendraLib.User storage user = users[wallets[i]];
            overview.globalPnl += user.globalPnl;
            overview.totalPositions += user.globalPosition.totalPositions;
            overview.activePositions += user.globalPosition.activePositions;
            overview.transactionCount += user.transactionCount;
        }
    }

    function getAccountingPositionCount(address _wallet) public view returns (uint256) {
        return accountingPositions[accountingRootOf(_wallet)].length;
    }

    function getAccountingPosition(address _wallet, uint256 _index)
        public
        view
        returns (address wallet, uint256 positionId, SendraLib.Position memory position)
    {
        SendraLib.PositionRef storage ref = accountingPositions[accountingRootOf(_wallet)][_index];
        wallet = ref.wallet;
        positionId = ref.positionId;
        position = users[wallet].globalPosition.positions[positionId];
    }

    function getPulseSnapshot(address _user) public view returns (SendraLib.PulseSnapshot memory snap) {
        address root = accountingRootOf(_user);
        SendraLib.SendraPulse storage pulse = users[root].pulse;
        snap.root = root;
        snap.syncVersion = pulse.syncVersion;
        snap.hasSeal = pulse.hasSeal;
        snap.sealedBaseVersion = pulse.sealedBaseVersion;
        snap.sealHash = pulse.hasSeal ? hashTemporalSeal(pulse.sealedPulse) : bytes32(0);
        snap.globalPulse = pulse.globalPulse;
        snap.temporalPulse = pulse.temporalPulse;
        snap.sealedPulse = pulse.sealedPulse;
    }

    /// @notice Commitment of the summable slice frozen in a seal. Timestamps and sequence metrics are excluded.
    function hashTemporalSeal(SendraLib.GlobalAccumulators memory _sealed) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _sealed.totalCapitalIn,
                _sealed.totalCapitalOut,
                _sealed.currentExposure,
                _sealed.cumulativeRealizedPnl,
                _sealed.grossProfit,
                _sealed.grossLoss,
                _sealed.totalPositionsOpened,
                _sealed.totalPositionsClosed,
                _sealed.winCount,
                _sealed.lossCount,
                _sealed.totalDurationSeconds,
                _sealed.totalLiquidationEvents,
                _sealed.totalLosingCapitalIn
            )
        );
    }

    /**
     * @notice Freezes the open temporal pulse so new activity cannot mix into a round that is already being synced.
     * @dev No-op when a seal is already open or there is nothing summable to freeze.
     *      The seal stays until commit clears it, including when the commit transaction reverts.
     */
    function sealTemporalPulse(address _user) external onlyPulseSyncer {
        address root = accountingRootOf(_user);
        SendraLib.SendraPulse storage pulse = users[root].pulse;
        if (pulse.hasSeal || _syncableIsZero(pulse.temporalPulse)) return;
        pulse.sealedPulse = pulse.temporalPulse;
        _zeroAccumulators(pulse.temporalPulse);
        pulse.hasSeal = true;
        pulse.sealedBaseVersion = pulse.syncVersion;
        emit TemporalSealed(root, pulse.syncVersion, hashTemporalSeal(pulse.sealedPulse));
    }

    /**
     * @notice Writes the absolute consolidated global and, when requested, clears the seal that was consumed.
     * @dev `expectedVersion` must match this chain. A retry with the same `newVersion` is a no-op, so a
     *      chain that already advanced cannot be rolled back to a stale global. `newVersion` may jump
     *      more than one when this chain is catching up to a global already published elsewhere.
     *      Open temporal activity is kept. Local sequence metrics are not overwritten.
     */
    function commitGlobalPulse(
        address _user,
        uint64 _expectedVersion,
        uint64 _newVersion,
        bool _clearSeal,
        bytes32 _consumedSealHash,
        uint256[] calldata _chainIds,
        bytes32[] calldata _sealHashes,
        SendraLib.GlobalAccumulators calldata _next
    ) external onlyPulseSyncer {
        if (_chainIds.length != _sealHashes.length) revert AccumulatorBatchLengthMismatch();
        address root = accountingRootOf(_user);
        SendraLib.SendraPulse storage pulse = users[root].pulse;
        if (pulse.syncVersion == _newVersion) return;
        if (pulse.syncVersion != _expectedVersion) revert StalePulseVersion(pulse.syncVersion, _expectedVersion);
        if (_newVersion <= _expectedVersion) revert InvalidPulseVersion();

        uint256 localFirst = pulse.globalPulse.firstActivityTimestamp;
        uint256 localLast = pulse.globalPulse.lastActivityTimestamp;
        _clearConsumedSeal(pulse, _clearSeal, _consumedSealHash);
        _assignSyncable(pulse.globalPulse, _next);
        pulse.globalPulse.firstActivityTimestamp = _earliest(localFirst, _next.firstActivityTimestamp);
        pulse.globalPulse.lastActivityTimestamp =
            localLast > _next.lastActivityTimestamp ? localLast : _next.lastActivityTimestamp;
        pulse.syncVersion = _newVersion;
        emit GlobalPulseCommitted(root, _newVersion, _consumedSealHash, _chainIds, _sealHashes);
    }

    /**
     * @notice EIP-712 digest both wallets must sign. Nonces are the current ones and change after a successful link.
     */
    function linkDigest(address _walletA, address _walletB, uint256 _deadline) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                LINK_TYPEHASH,
                _walletA,
                _walletB,
                linkNonce[_walletA],
                linkNonce[_walletB],
                _deadline
            )
        );
        return MessageHashUtils.toTypedDataHash(_domainSeparator(), structHash);
    }

    /**
     * @notice Joins two wallets into one accounting user. Both signatures are required; either side may submit.
     * @dev One transaction, no stored approval. A wallet already in another group is merged in, up to 16 wallets.
     *      Positions stay on the wallet that opened them and are indexed on the surviving root.
     *      Pending pulse on the joined root is folded into the survivor's temporal pulse.
     */
    function linkWallets(
        address _walletA,
        address _walletB,
        uint256 _deadline,
        bytes calldata _signatureA,
        bytes calldata _signatureB
    ) external {
        if (_walletA == address(0) || _walletB == address(0) || _walletA == _walletB) revert InvalidLink();
        if (_deadline < block.timestamp) revert LinkExpired();
        bytes32 digest = linkDigest(_walletA, _walletB, _deadline);
        if (!_validSignature(_walletA, digest, _signatureA) || !_validSignature(_walletB, digest, _signatureB)) {
            revert InvalidLinkSignature();
        }
        linkNonce[_walletA]++;
        linkNonce[_walletB]++;
        _joinGroups(_walletA, _walletB);
    }

    function _touchRoot(address _wallet) private returns (address root) {
        root = accountingRootOf(_wallet);
        if (users[root].id == 0) createUser(root);
    }

    function _domainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("SendraStorage")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function _validSignature(address _wallet, bytes32 _digest, bytes calldata _signature) private view returns (bool) {
        if (_signature.length == 65) {
            (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(_digest, _signature);
            if (err == ECDSA.RecoverError.NoError && recovered == _wallet) return true;
        }
        if (_wallet.code.length == 0) return false;
        try IERC1271(_wallet).isValidSignature(_digest, _signature) returns (bytes4 magic) {
            return magic == IERC1271.isValidSignature.selector;
        } catch {
            return false;
        }
    }

    function _joinGroups(address _walletA, address _walletB) private {
        address rootA = accountingRootOf(_walletA);
        address rootB = accountingRootOf(_walletB);
        if (rootA == rootB) revert AlreadyLinked();

        uint256 countA = linkedWallets[rootA].length == 0 ? 1 : linkedWallets[rootA].length;
        uint256 countB = linkedWallets[rootB].length == 0 ? 1 : linkedWallets[rootB].length;
        if (countA + countB > MAX_LINKED_WALLETS) revert LinkWalletLimit();

        (address survivor, address joiner) = _preferRoot(rootA, rootB);
        _ensureGroup(survivor);

        if (linkedWallets[joiner].length == 0) {
            walletRoot[joiner] = survivor;
            linkedWallets[survivor].push(joiner);
        } else {
            address[] memory members = linkedWallets[joiner];
            for (uint256 i = 0; i < members.length; i++) {
                walletRoot[members[i]] = survivor;
                linkedWallets[survivor].push(members[i]);
            }
            delete linkedWallets[joiner];
        }

        _foldPulse(joiner, survivor);
        _movePositionIndex(joiner, survivor);
        emit WalletsLinked(survivor, joiner, linkedWallets[survivor].length);
    }

    function _ensureGroup(address _root) private {
        if (linkedWallets[_root].length == 0) {
            walletRoot[_root] = _root;
            linkedWallets[_root].push(_root);
        }
    }

    function _preferRoot(address _a, address _b) private view returns (address survivor, address joiner) {
        uint256 idA = users[_a].id;
        uint256 idB = users[_b].id;
        bool preferA = true;
        if (idA == 0 && idB != 0) preferA = false;
        else if (idA != 0 && idB != 0 && idB < idA) preferA = false;
        else if (idA == 0 && idB == 0 && _b < _a) preferA = false;
        if (preferA) return (_a, _b);
        return (_b, _a);
    }

    function _foldPulse(address _from, address _to) private {
        if (_from == _to) return;
        SendraLib.SendraPulse storage src = users[_from].pulse;
        SendraLib.SendraPulse storage dst = users[_to].pulse;
        _addSyncable(dst.temporalPulse, src.globalPulse);
        _addSyncable(dst.temporalPulse, src.temporalPulse);
        _addSyncable(dst.temporalPulse, src.sealedPulse);
        dst.globalPulse.firstActivityTimestamp =
            _earliest(dst.globalPulse.firstActivityTimestamp, src.globalPulse.firstActivityTimestamp);
        if (src.globalPulse.lastActivityTimestamp > dst.globalPulse.lastActivityTimestamp) {
            dst.globalPulse.lastActivityTimestamp = src.globalPulse.lastActivityTimestamp;
        }
        _mergeLocal(dst.globalPulse, src.globalPulse);
        _zeroAccumulators(src.globalPulse);
        _zeroAccumulators(src.temporalPulse);
        _zeroAccumulators(src.sealedPulse);
        src.hasSeal = false;
        src.sealedBaseVersion = 0;
        src.syncVersion = 0;
    }

    function _movePositionIndex(address _from, address _to) private {
        if (_from == _to) return;
        SendraLib.PositionRef[] storage src = accountingPositions[_from];
        uint256 n = src.length;
        for (uint256 i = 0; i < n; i++) {
            accountingPositions[_to].push(src[i]);
        }
        delete accountingPositions[_from];
    }

    function _clearConsumedSeal(SendraLib.SendraPulse storage _pulse, bool _clearSeal, bytes32 _consumedSealHash) private {
        if (!_clearSeal) {
            if (_consumedSealHash != bytes32(0)) {
                bytes32 currentHash = _pulse.hasSeal ? hashTemporalSeal(_pulse.sealedPulse) : bytes32(0);
                revert SealHashMismatch(currentHash, _consumedSealHash);
            }
            return;
        }
        bytes32 sealHash = _pulse.hasSeal ? hashTemporalSeal(_pulse.sealedPulse) : bytes32(0);
        if (sealHash != _consumedSealHash) revert SealHashMismatch(sealHash, _consumedSealHash);
        if (_pulse.hasSeal) {
            _zeroAccumulators(_pulse.sealedPulse);
            _pulse.hasSeal = false;
            _pulse.sealedBaseVersion = 0;
        }
    }

    function _assignSyncable(SendraLib.GlobalAccumulators storage _dst, SendraLib.GlobalAccumulators calldata _src) private {
        _dst.totalCapitalIn = _src.totalCapitalIn;
        _dst.totalCapitalOut = _src.totalCapitalOut;
        _dst.currentExposure = _src.currentExposure;
        _dst.cumulativeRealizedPnl = _src.cumulativeRealizedPnl;
        _dst.grossProfit = _src.grossProfit;
        _dst.grossLoss = _src.grossLoss;
        _dst.totalPositionsOpened = _src.totalPositionsOpened;
        _dst.totalPositionsClosed = _src.totalPositionsClosed;
        _dst.winCount = _src.winCount;
        _dst.lossCount = _src.lossCount;
        _dst.totalDurationSeconds = _src.totalDurationSeconds;
        _dst.totalLiquidationEvents = _src.totalLiquidationEvents;
        _dst.totalLosingCapitalIn = _src.totalLosingCapitalIn;
    }

    function _addSyncable(SendraLib.GlobalAccumulators storage _dst, SendraLib.GlobalAccumulators storage _src) private {
        _dst.totalCapitalIn += _src.totalCapitalIn;
        _dst.totalCapitalOut += _src.totalCapitalOut;
        _dst.currentExposure += _src.currentExposure;
        _dst.cumulativeRealizedPnl += _src.cumulativeRealizedPnl;
        _dst.grossProfit += _src.grossProfit;
        _dst.grossLoss += _src.grossLoss;
        _dst.totalPositionsOpened += _src.totalPositionsOpened;
        _dst.totalPositionsClosed += _src.totalPositionsClosed;
        _dst.winCount += _src.winCount;
        _dst.lossCount += _src.lossCount;
        _dst.totalDurationSeconds += _src.totalDurationSeconds;
        _dst.totalLiquidationEvents += _src.totalLiquidationEvents;
        _dst.totalLosingCapitalIn += _src.totalLosingCapitalIn;
    }

    function _mergeLocal(SendraLib.GlobalAccumulators storage _dst, SendraLib.GlobalAccumulators storage _src) private {
        if (_src.peakSimultaneousExposure > _dst.peakSimultaneousExposure) {
            _dst.peakSimultaneousExposure = _src.peakSimultaneousExposure;
        }
        if (_src.highWaterMark > _dst.highWaterMark) _dst.highWaterMark = _src.highWaterMark;
        if (_src.maxDrawdown > _dst.maxDrawdown) _dst.maxDrawdown = _src.maxDrawdown;
        if (_src.maxConsecutiveLosses > _dst.maxConsecutiveLosses) {
            _dst.maxConsecutiveLosses = _src.maxConsecutiveLosses;
        }
    }

    function _zeroAccumulators(SendraLib.GlobalAccumulators storage _g) private {
        uint256 slot;
        assembly {
            slot := _g.slot
        }
        for (uint256 i = 0; i < GLOBAL_ACC_FIELD_COUNT; i++) {
            uint256 word = slot + i;
            assembly {
                sstore(word, 0)
            }
        }
    }

    function _syncableIsZero(SendraLib.GlobalAccumulators storage _g) private view returns (bool) {
        return _g.totalCapitalIn == 0 && _g.totalCapitalOut == 0 && _g.currentExposure == 0
            && _g.cumulativeRealizedPnl == 0 && _g.grossProfit == 0 && _g.grossLoss == 0
            && _g.totalPositionsOpened == 0 && _g.totalPositionsClosed == 0 && _g.winCount == 0 && _g.lossCount == 0
            && _g.totalDurationSeconds == 0 && _g.totalLiquidationEvents == 0 && _g.totalLosingCapitalIn == 0;
    }

    function _earliest(uint256 _a, uint256 _b) private pure returns (uint256) {
        if (_a == 0) return _b;
        if (_b == 0) return _a;
        return _a < _b ? _a : _b;
    }

}
