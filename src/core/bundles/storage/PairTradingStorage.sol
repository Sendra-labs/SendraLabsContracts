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
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒                                                                                                                                                    
________________________________________________________________
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PairTradingLib } from "../../../lib/PairTrading/PairTradingLib.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { ProxyAccessControl } from "../security/proxyAccessControl.sol";

/**
 * @title PairTradingStorage
 * @notice Storage contract for PairTrading execution data and position tracking
 * @dev Manages raw execution data from GMX order callbacks, pending orders, and position information
 *      for PairTrading strategies. This contract serves as the central storage layer for all
 *      market neutral position-related data.
 * 
 *      Key features:
 *      - Stores raw execution data from GMX callbacks
 *      - Tracks pending orders by user
 *      - Maintains position information mappings
 *      - Access control for protocol contracts and proxies
 */
contract PairTradingStorage {
    
    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /**
     * @notice Constructs the PairTradingStorage contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    /**
     * @notice Modifier that restricts access to authorized protocol contracts and proxies only
     * @dev Verifies that the caller is either:
     *      1. A registered protocol contract (via Roles)
     *      2. A registered protocol proxy (via ProxyAccessControl)
     * @custom:revert InvalidProtocol If the caller is not authorized
     */
    modifier onlyProtocol() {
        if(
            !Roles(addressProvider.getAddress("Roles")).isProtocolContract(msg.sender)
            && !ProxyAccessControl(addressProvider.getAddress("ProxyAccessControl")).isProtocolProxy(msg.sender)
        ) revert InvalidProtocol();
        _;
    }
    
    /// @notice Thrown when a function is called by an unauthorized address
    error InvalidProtocol();
    
    /// @notice Mapping from order key to raw execution data from GMX callbacks
    mapping(bytes32 => PairTradingLib.RawExecutionData) public rawExecutionData;
    
    /// @notice Mapping from position key to position information
    mapping(bytes32 => PositionInfo) public positionInfo;
    
    /**
     * @notice Structure storing position information
     * @param account Address of the position owner
     * @param market Address of the GMX market
     * @param collateralToken Address of the collateral token (WETH or USDC)
     * @param isLong Whether this is a long (true) or short (false) position
     * @param positionId ID of the position in ProtocolStorage
     * @param isActive Whether the position is currently active
     */
    struct PositionInfo {
        address account;
        address market;
        address collateralToken;
        bool isLong;
        uint256 positionId;
        bool isActive;
    }
    
    // Events

    /**
     * @notice Emitted when raw execution data is stored
     * @param orderKey The order key from GMX
     * @param positionId The position ID associated with the order
     * @param receiver Address that will receive the funds
     */
    event RawExecutionDataStored(bytes32 indexed orderKey, uint256 indexed positionId, address indexed receiver);
    
    /**
     * @notice Emitted when position information is stored
     * @param positionKey The position key (keccak256 hash)
     * @param account Address of the position owner
     * @param market Address of the GMX market
     */
    event PositionInfoStored(bytes32 indexed positionKey, address indexed account, address indexed market);
    

    /// @notice Mapping from order key to pending order information
    mapping(bytes32 => PairTradingLib.PendingOrder) public pendingOrders;
    
    /// @notice Mapping from user address to array of their pending order keys
    mapping(address => bytes32[]) public userPendingOrderKeys;

    /**
     * @notice Adds a pending order key to a user's list
     * @dev Called when an order is created to track pending orders per user
     * @param _user Address of the user
     * @param _key Order key to add
     * @custom:require Only callable by protocol contracts or proxies
     */
    function addUserPendingOrderKey(address _user, bytes32 _key) public onlyProtocol {
        userPendingOrderKeys[_user].push(_key);
    }

    /**
     * @notice Helper function to remove a value from an array using swap-and-pop
     * @dev Efficiently removes an element by swapping with the last element and popping
     * @param array Storage reference to the array
     * @param value Value to remove from the array
     */
    function removeFromArray(bytes32[] storage array, bytes32 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                return;
            }
        }
    }

    /**
     * @notice Removes a pending order key from a user's list
     * @dev Called when an order is processed or cancelled
     * @param _user Address of the user
     * @param _key Order key to remove
     * @custom:require Only callable by protocol contracts or proxies
     */
    function removeUserPendingOrderKey(address _user, bytes32 _key) public onlyProtocol {
        removeFromArray(userPendingOrderKeys[_user], _key);
    }

    /**
     * @notice Gets all pending order keys for a user
     * @param _user Address of the user
     * @return Array of order keys for pending orders
     */
    function getUserPendingOrderKeys(address _user) public view returns(bytes32[] memory) {
        return userPendingOrderKeys[_user];
    }
    
    /**
     * @notice Updates or stores a pending order
     * @dev Stores pending order information that links order keys to position data
     * @param _key Order key from GMX
     * @param _pendingOrder Pending order data containing receiver, proxy, positionId, etc.
     * @custom:require Only callable by protocol contracts or proxies
     */
    function updatePendingOrder(bytes32 _key, PairTradingLib.PendingOrder memory _pendingOrder) public onlyProtocol {
        pendingOrders[_key] = _pendingOrder;
    }

    /**
     * @notice Retrieves pending order information by order key
     * @param _key Order key from GMX
     * @return Pending order data structure
     */
    function getPendingOrder(bytes32 _key) public view returns(PairTradingLib.PendingOrder memory) {
        return pendingOrders[_key];
    }
    
    /**
     * @notice Stores raw execution data from GMX order callbacks
     * @dev Called by ClosePositionCallbacks when an order is executed.
     *      Stores execution details like output token, amount, prices, and PNL.
     * @param orderKey The order key from GMX
     * @param data Raw execution data structure containing all execution details
     * @custom:require Only callable by protocol contracts or proxies
     * @custom:emit RawExecutionDataStored Emitted after successful storage
     */
    function storeRawExecutionData(bytes32 orderKey, PairTradingLib.RawExecutionData memory data) external onlyProtocol {
        rawExecutionData[orderKey] = data;
        emit RawExecutionDataStored(orderKey, data.positionId, data.receiver);
    }
    
    /**
     * @notice Stores position information for tracking
     * @dev Links position keys to account, market, and position details
     * @param positionKey The position key (keccak256 hash of account, market, collateral, isLong)
     * @param info Position information structure
     * @custom:require Only callable by protocol contracts or proxies
     * @custom:emit PositionInfoStored Emitted after successful storage
     */
    function storePositionInfo(bytes32 positionKey, PositionInfo memory info) external onlyProtocol {
        positionInfo[positionKey] = info;
        emit PositionInfoStored(positionKey, info.account, info.market);
    }
    
    /**
     * @notice Retrieves raw execution data by order key
     * @param orderKey The order key from GMX
     * @return data Raw execution data structure
     */
    function getRawExecutionData(bytes32 orderKey) external view returns (PairTradingLib.RawExecutionData memory data) {
        return rawExecutionData[orderKey];
    }
    
    /**
     * @notice Retrieves position information by position key
     * @param positionKey The position key (keccak256 hash)
     * @return info Position information structure
     */
    function getPositionInfo(bytes32 positionKey) external view returns (PositionInfo memory info) {
        return positionInfo[positionKey];
    }
    
    /**
     * @notice Updates the processed status of raw execution data
     * @dev Marks execution data as processed after funds have been transferred to the user
     * @param orderKey The order key from GMX
     * @param processed Whether the execution data has been processed
     * @custom:require Only callable by protocol contracts or proxies
     */
    function updateExecutionProcessed(bytes32 orderKey, bool processed) external onlyProtocol {
        rawExecutionData[orderKey].processed = processed;
    }
    
    /**
     * @notice Updates the active status of a position
     * @dev Used to mark positions as inactive when closed
     * @param positionKey The position key (keccak256 hash)
     * @param isActive Whether the position is currently active
     * @custom:require Only callable by protocol contracts or proxies
     */
    function updatePositionStatus(bytes32 positionKey, bool isActive) external onlyProtocol {
        positionInfo[positionKey].isActive = isActive;
    }
}