/*

REBEL type ASCII art

 ███████████ ████                           ███████████  ███ 
▒▒███▒▒▒▒▒▒█▒▒███                          ▒▒███▒▒▒▒▒▒█ ▒▒▒  
 ▒███   █ ▒  ▒███   ██████  █████ ███ █████ ▒███   █ ▒  ████ 
 ▒███████    ▒███  ███▒▒███▒▒███ ▒███▒▒███  ▒███████   ▒▒███ 
 ▒███▒▒▒█    ▒███ ▒███ ▒███ ▒███ ▒███ ▒███  ▒███▒▒▒█    ▒███ 
 ▒███  ▒     ▒███ ▒███ ▒███ ▒▒███████████   ▒███  ▒     ▒███ 
 █████       █████▒▒██████   ▒▒████▒████    █████       █████
▒▒▒▒▒       ▒▒▒▒▒  ▒▒▒▒▒▒     ▒▒▒▒ ▒▒▒▒    ▒▒▒▒▒       ▒▒▒▒▒ 
                                                             
                                                                              
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolLib } from "../lib/Protocol.lib.sol";
import { Roles } from "../security/Roles.sol";

/**
 * @title ProtocolStorage
 * @author @Diego-AVZ
 * @notice Centralized storage contract for protocol data and statistics
 * @dev Manages user data, protocol statistics, and provides controlled access to storage operations
 * @dev Only authorized protocol contracts can modify data through onlyProtocol modifier
 * @custom:security All write operations require protocol contract authorization
 */
contract ProtocolStorage {
    
    /// @notice Reference to the Roles contract for access control
    Roles public roles;

    /**
     * @notice Initializes the ProtocolStorage with Roles contract
     * @param _roles Address of the Roles contract for protocol contract verification
     */
    constructor(address _roles) {
        roles = Roles(_roles);
    }

    /**
     * @notice Modifier that restricts access to authorized protocol contracts only
     * @dev Uses Roles contract to verify that caller is a registered protocol contract
     */
    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert InvalidProtocol();
        _;
    }

    /// @notice Thrown when an unauthorized contract attempts to access storage
    error InvalidProtocol();

    /// @notice Protocol statistics stored in a single struct for efficiency
    ProtocolLib.ProtocolStats internal protocolStats;

    /// @notice Mapping of user addresses to their User data
    mapping(address => ProtocolLib.User) public users;

    /**
     * @notice Creates a new user in the protocol
     * @dev Only callable by authorized protocol contracts
     * @param _user The address of the user to create
     * @custom:security Only protocol contracts can create users
    */
    function createUser(address _user) internal onlyProtocol {
        protocolStats.totalUsers++;
        users[_user] = ProtocolLib.User(protocolStats.totalUsers, 0, ProtocolLib.GlobalPosition(0, 0, new ProtocolLib.Position[](0)), 0, new bytes[](0));
    }

    function updateUserGlobalPnl(address _user, int256 _pnlChange) public onlyProtocol {
        ProtocolLib.User memory updatedUser = users[_user];
        updatedUser.globalPnl += _pnlChange;
        updateUser(_user, updatedUser);
    }

    function updateUserTransactionCount(address _user, uint256 _transactionCount) public onlyProtocol {
        ProtocolLib.User memory updatedUser = users[_user];
        updatedUser.transactionCount += _transactionCount;
        updateUser(_user, updatedUser);
    }

    function updateUserGlobalPosition(address _user, ProtocolLib.GlobalPosition memory _globalPosition) public onlyProtocol {
        ProtocolLib.User memory updatedUser = users[_user];
        updatedUser.globalPosition = _globalPosition;
        updateUser(_user, updatedUser);
    }

    function updateUser(address _user, ProtocolLib.User memory _userData) internal {
        if (!isUser(_user)) createUser(_user);
        users[_user] = _userData;
    }

    function finalizePosition(uint256 _positionId, address _user) external onlyProtocol {
        ProtocolLib.GlobalPosition memory userGlobalPosition = getUser(_user).globalPosition;
        
        (,uint256 index) = getUserPosition(userGlobalPosition.positions, _positionId);

        ProtocolLib.Position[] memory _updatedPositions = userGlobalPosition.positions;

        _updatedPositions[index].isActive = false;
        
        updateUserGlobalPosition(
            _user, 
            ProtocolLib.GlobalPosition(
                userGlobalPosition.totalPositions, 
                userGlobalPosition.activePositions - 1,
                _updatedPositions
            )
        );
    }

    function getUserPosition(ProtocolLib.Position[] memory _positions, uint256 _positionId) public pure returns (ProtocolLib.Position memory, uint256 index) {
        for(uint256 i = 0; i < _positions.length; i++) {
            if(_positions[i].id == _positionId) {
                return (_positions[i], i);
            }
        }
        revert("Position not found");
    }

    function getUserPositionById(address _user, uint256 _positionId) public view returns (ProtocolLib.Position memory position) {
        (position, ) = getUserPosition(users[_user].globalPosition.positions, _positionId);
        return position;
    }

    function isUser(address _user) public view returns(bool) {
        return users[_user].id != 0;
    }

    /**
     * @notice Retrieves user data for a specific address
     * @param _user The address of the user to query
     * @return User struct containing all user data
     */
    function getUser(address _user) public view returns(ProtocolLib.User memory) {
        return users[_user];
    }

    /**
     * @notice Returns the total number of users in the protocol
     * @return Total number of users registered
     */
    function getUsersCount() public view returns(uint256) {
        return protocolStats.totalUsers;
    }

    /**
     * @notice Returns all protocol statistics
     * @return ProtocolStats struct containing all protocol metrics
     */
    function getProtocolStats() public view returns(ProtocolLib.ProtocolStats memory) {
        return protocolStats;
    }

    /**
     * @notice Updates the total volume processed by the protocol
     * @dev Only callable by authorized protocol contracts
     * @param _amount The amount to add to total volume
     * @custom:security Only protocol contracts can update volume
     */
    function updateTotalVolume(uint256 _amount) public onlyProtocol {
        protocolStats.totalVolume += _amount;
    }

    /**
     * @notice Updates the total PnL of the protocol
     * @dev Only callable by authorized protocol contracts. Handles both positive and negative PnL
     * @param _pnl The PnL change (positive or negative)
     * @custom:security Only protocol contracts can update PnL. Prevents underflow
     */
    function updateTotalPnl(int256 _pnl) public onlyProtocol {
        protocolStats.totalPnl += _pnl;
    }

    /**
     * @notice Increments the total transaction count
     * @dev Only callable by authorized protocol contracts
     * @custom:security Only protocol contracts can update transaction count
     */
    function updateTotalTransactions() public onlyProtocol {
        protocolStats.totalTransactions++;
    }

    /**
     * @notice Increments the total positions count
     * @dev Only callable by authorized protocol contracts
     * @custom:security Only protocol contracts can update positions count
     */
    function updateTotalPositions() public onlyProtocol {
        protocolStats.totalPositions++;
    }

    /**
     * @notice Updates the total active positions count
     * @dev Only callable by authorized protocol contracts. Handles both increases and decreases
     * @param _change The change in active positions (positive or negative)
     * @custom:security Only protocol contracts can update active positions. Prevents underflow
     */
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

    /**
     * @notice Updates the total value locked in the protocol
     * @dev Only callable by authorized protocol contracts. Handles both increases and decreases
     * @param _change The change in total value locked (positive or negative)
     * @custom:security Only protocol contracts can update TVL. Prevents underflow
     */
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