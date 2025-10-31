//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolLib } from "../lib/Protocol.lib.sol";
import { Roles } from "../security/Roles.sol";

/**
 * @title UpgradeableLib
 * @author @Diego-AVZ
 * @notice Dynamic configuration system for protocol positions and user data
 * @dev Enables adding new position types and user data fields without contract redeployment
 * @dev Implements admin-controlled dynamic structures for maximum protocol flexibility
 * @custom:security All modifications require admin consensus through Roles contract
 */
contract UpgradeableLib {

    /// @notice Reference to the Roles contract for access control
    Roles public roles;

    /**
     * @notice Initializes the UpgradeableLib with Roles contract and default position type
     * @param _roles Address of the Roles contract for admin verification
     * @dev Creates initial "Fund" position type with amount and tokenAddress parameters
     */
    constructor(address _roles) {
        roles = Roles(_roles);
        ProtocolLib.PositionParam[] memory _params = new ProtocolLib.PositionParam[](2);
        _params[0] = ProtocolLib.PositionParam(0, "amount");
        _params[1] = ProtocolLib.PositionParam(1, "tokenAddress");

        /*addPositionType(
            ProtocolLib.PositionType(
                "Fund",
                0,
                _params
            )
        );*/
    }

    /**
     * @notice Modifier that restricts access to admin addresses only
     * @dev Uses Roles contract to verify admin status
     */
    modifier onlyAdmin() {
        if(!roles.checkAdmin(msg.sender)) revert InvalidSigner();
        _;
    }

    /// @notice Thrown when an unauthorized address attempts to perform an admin action
    error InvalidSigner();

    /// @notice Counter for total position types registered
    uint256 public positionsTypesCount;
    
    /// @notice Counter for total user data fields registered
    uint256 public userDataFieldsCount;
    
    /// @notice Mapping of position type ID to PositionType struct
    mapping(uint256 => ProtocolLib.PositionType) public positionsTypes;
    
    /// @notice Mapping of user data field ID to UserDataField struct
    mapping(uint256 => ProtocolLib.UserDataField) public userDataFields;
 
    /**
     * @notice Adds a new position type to the protocol
     * @dev Only callable by admin addresses. Enables dynamic addition of new position types
     * @param _positionType The PositionType struct containing name, origin, and parameters
     * @custom:security Only admin addresses can add new position types
     */
    function addPositionType(ProtocolLib.PositionType memory _positionType) public onlyAdmin {
        positionsTypes[positionsTypesCount] = _positionType;
        positionsTypesCount++;
    }

    /**
     * @notice Returns the total number of registered position types
     * @return Number of position types currently registered
     */
    function getPositionsTypesCount() public view returns(uint256) {
        return positionsTypesCount;
    }

    /**
     * @notice Returns a specific position type by ID
     * @param _id The ID of the position type to retrieve
     * @return PositionType struct containing name, origin, and parameters
    */
    function getPositionType(uint256 _id) public view returns(ProtocolLib.PositionType memory) {
        return positionsTypes[_id];
    }

    /**
     * @notice Returns all registered position types
     * @return Array of all PositionType structs currently registered
     */
    function getPositionsTypes() public view returns(ProtocolLib.PositionType[] memory) {
        ProtocolLib.PositionType[] memory _positionsTypes = new ProtocolLib.PositionType[](positionsTypesCount);
        for(uint256 i = 0; i < positionsTypesCount; i++) {
            _positionsTypes[i] = positionsTypes[i];
        }
        return _positionsTypes;
    }

    /**
     * @notice Adds a new user data field to the protocol
     * @dev Only callable by admin addresses. Enables dynamic addition of new user data fields
     * @param _userDataField The UserDataField struct containing field name and type
     * @custom:security Only admin addresses can add new user data fields
     */
    function addUserDataField(ProtocolLib.UserDataField memory _userDataField) public onlyAdmin {
        userDataFields[userDataFieldsCount] = _userDataField;
        userDataFieldsCount++;
    }

    /**
     * @notice Returns the total number of registered user data fields
     * @return Number of user data fields currently registered
     */
    function getUserDataFieldsCount() public view returns(uint256) {
        return userDataFieldsCount;
    }

    /**
     * @notice Returns a specific user data field by ID
     * @param _id The ID of the user data field to retrieve
     * @return UserDataField struct containing field name and type
     */
    function getUserDataField(uint256 _id) public view returns(ProtocolLib.UserDataField memory) {
        return userDataFields[_id];
    }

    /**
     * @notice Returns all registered user data fields
     * @return Array of all UserDataField structs currently registered
     */
    function getUserDataFields() public view returns(ProtocolLib.UserDataField[] memory) {
        ProtocolLib.UserDataField[] memory _userDataFields = new ProtocolLib.UserDataField[](userDataFieldsCount);
        for(uint256 i = 0; i < userDataFieldsCount; i++) {
            _userDataFields[i] = userDataFields[i];
        }
        return _userDataFields;
    }

}