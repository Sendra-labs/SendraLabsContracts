//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MarketNeutralLib } from "../../../lib/MarketNeutral/MarketNeutralLib.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { Roles } from "../../../security/Roles.sol";

/**
 * @title MarketNeutralStorage
 * @notice Storage contract for MarketNeutral execution data
 * @dev Manages raw execution data and position keys for MarketNeutral strategies
 */
contract MarketNeutralStorage {
    
    /// @notice Reference to the Roles contract for access control
    Roles public roles;
    
    /**
     * @notice Initializes the MarketNeutralStorage with Roles contract
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
    
    error InvalidProtocol();
    
    mapping(bytes32 => MarketNeutralLib.RawExecutionData) public rawExecutionData;
    
    mapping(bytes32 => PositionInfo) public positionInfo;
    
    struct PositionInfo {
        address account;
        address market;
        address collateralToken;
        bool isLong;
        uint256 positionId;
        bool isActive;
    }
    
    // Events
    event RawExecutionDataStored(bytes32 indexed orderKey, uint256 indexed positionId, address indexed receiver);
    event PositionInfoStored(bytes32 indexed positionKey, address indexed account, address indexed market);
    

    mapping(bytes32 => MarketNeutralLib.PendingOrder) public pendingOrders;
    mapping(address => bytes32[]) public userPendingOrderKeys;

    function addUserPendingOrderKey(address _user, bytes32 _key) public onlyProtocol {
        userPendingOrderKeys[_user].push(_key);
    }

    function removeFromArray(bytes32[] storage array, bytes32 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                return;
            }
        }
    }

    function removeUserPendingOrderKey(address _user, bytes32 _key) public onlyProtocol {
        removeFromArray(userPendingOrderKeys[_user], _key);
    }

    function getUserPendingOrderKeys(address _user) public view returns(bytes32[] memory) {
        return userPendingOrderKeys[_user];
    }
    
    function updatePendingOrder(bytes32 _key, MarketNeutralLib.PendingOrder memory _pendingOrder) public onlyProtocol {
        pendingOrders[_key] = _pendingOrder;
    }

    function getPendingOrder(bytes32 _key) public view returns(MarketNeutralLib.PendingOrder memory) {
        return pendingOrders[_key];
    }
    
    /**
     * @notice Almacena datos de ejecución crudos
     * @param orderKey La clave de la orden
     * @param data Los datos de ejecución
     */
    function storeRawExecutionData(bytes32 orderKey, MarketNeutralLib.RawExecutionData memory data) external onlyProtocol {
        rawExecutionData[orderKey] = data;
        emit RawExecutionDataStored(orderKey, data.positionId, data.receiver);
    }
    
    /**
     * @notice Almacena información de posición
     * @param positionKey La clave de la posición
     * @param info La información de la posición
     */
    function storePositionInfo(bytes32 positionKey, PositionInfo memory info) external onlyProtocol {
        positionInfo[positionKey] = info;
        emit PositionInfoStored(positionKey, info.account, info.market);
    }
    
    /**
     * @notice Obtiene datos de ejecución crudos
     * @param orderKey La clave de la orden
     * @return data Los datos de ejecución
     */
    function getRawExecutionData(bytes32 orderKey) external view returns (MarketNeutralLib.RawExecutionData memory data) {
        return rawExecutionData[orderKey];
    }
    
    /**
     * @notice Obtiene información de posición
     * @param positionKey La clave de la posición
     * @return info La información de la posición
     */
    function getPositionInfo(bytes32 positionKey) external view returns (PositionInfo memory info) {
        return positionInfo[positionKey];
    }
    
    /**
     * @notice Actualiza el estado de procesamiento de datos de ejecución
     * @param orderKey La clave de la orden
     * @param processed Si ya fue procesado
     */
    function updateExecutionProcessed(bytes32 orderKey, bool processed) external onlyProtocol {
        rawExecutionData[orderKey].processed = processed;
    }
    
    /**
     * @notice Actualiza el estado de una posición
     * @param positionKey La clave de la posición
     * @param isActive Si está activa
     */
    function updatePositionStatus(bytes32 positionKey, bool isActive) external onlyProtocol {
        positionInfo[positionKey].isActive = isActive;
    }
}