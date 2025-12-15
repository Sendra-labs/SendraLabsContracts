/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒        PROTOCOL STORAGE                                                                                                                                  
________________________________________________________________
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
    mapping(address => ProtocolLib.User) internal users;

    /**
     * @notice Creates a new user in the protocol
     * @dev Only callable by authorized protocol contracts
     * @param _user The address of the user to create
     * @custom:security Only protocol contracts can create users
    */
    function createUser(address _user) internal onlyProtocol {
        protocolStats.totalUsers++;
        ProtocolLib.User storage newUser = users[_user];
        newUser.id = protocolStats.totalUsers;
        newUser.globalPnl = 0;
        newUser.globalPosition.totalPositions = 0;
        newUser.globalPosition.activePositions = 0;
        newUser.transactionCount = 0;
    }
    
    /**
     * @notice Getter for users mapping (required because cannot be public with nested mappings)
     * @param _user The address of the user
     * @return User struct (note: cannot return nested mapping, use getUserPositionById instead)
     */
    function getUser(address _user) public view returns(ProtocolLib.UserInfoRead memory) {
        ProtocolLib.User storage user = users[_user];
        
        return ProtocolLib.UserInfoRead(
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
        ProtocolLib.User storage user = users[_user];
        user.transactionCount += _transactionCount;
    }

    function finalizePosition(uint256 _positionId, address _user) external onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].isActive = false;
        user.globalPosition.activePositions--;
    }

    // NEW FUNCTIONS STORAGE v2

    function addPositionToUser(address _user, ProtocolLib.Position memory _position) public onlyProtocol {
        if (!isUser(_user)) createUser(_user);
        ProtocolLib.User storage user = users[_user];
        user.transactionCount++;
        user.globalPosition.totalPositions++;
        user.globalPosition.activePositions++;
        user.globalPosition.positions[user.globalPosition.totalPositions] = _position;
    }

    function updateUserFullPosition(address _user, uint256 _positionId, ProtocolLib.Position memory _position) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId] = _position;
    }

    function updateUserPositionData(address _user, uint256 _positionId, uint256 _positionField, bytes memory _value) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        if(_positionField >= user.globalPosition.positions[_positionId].positionData.length) {
            user.globalPosition.positions[_positionId].positionData.push(_value);
        } else {
            user.globalPosition.positions[_positionId].positionData[_positionField] = _value;
        }
    }

    function updateUserPositionPnl(address _user, uint256 _positionId, int256 _pnlChange) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].pnl += _pnlChange;
    }

    function updateUserPositionIsActive(address _user, uint256 _positionId, bool _isActive) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPosition.positions[_positionId].isActive = _isActive;
    }

    function updateUserGlobalPnl(address _user, int256 _pnlChange) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPnl += _pnlChange;
    }

    function addUserData(ProtocolLib.User storage _user, bytes memory _data) internal {
        _user.userData.push(_data);
    }

    function updateUserData(address _user, uint256 _dataIndex, bytes memory _data) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        if(_dataIndex >= user.userData.length) {
            addUserData(user, _data);
        } else {
            user.userData[_dataIndex] = _data;
        }
    }

    function decreaseGlobalPositionActivePositions(address _user) public onlyProtocol {
        ProtocolLib.User storage user = users[_user];
        user.globalPosition.activePositions--;
    }

    //____________


    function getUserPositionById(address _user, uint256 _positionId) public view returns (ProtocolLib.Position memory position) {
        position = users[_user].globalPosition.positions[_positionId];
        return position;
    }

    function isUser(address _user) public view returns(bool) {
        return users[_user].id != 0;
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