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

import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";


/**
 * @title HoldingsPositionManager
 * @notice Contract responsible for initializing new positions in the protocol storage
 * @dev This contract handles the creation and initialization of new positions for users.
 *      It manages position IDs, transaction counts, and position data storage.
 *      Access is restricted to protocol contracts and registered protocol proxies.
 */
contract HoldingsPositionManager {

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /// @notice Roles contract for access control verification
    Roles public immutable roles;

    /**
     * @notice Constructs the HoldingsPositionManager contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    /**
     * @notice Modifier to restrict access to protocol contracts and registered proxies only
     * @dev Checks if the caller is a registered protocol contract (via Roles)
     * @custom:revert SenderNotAllowed If the caller is not authorized
     */
    modifier onlyProtocol() {
        if(
            !roles.isProtocolContract(msg.sender)
        ) 
        revert SenderNotAllowed();
        _;
    }

    /**
     * @notice Initializes a new position for a user in the protocol storage
     * @dev Creates a new position entry with the provided data:
     *      - Increments the user's transaction count
     *      - Generates a new position ID (sequential, based on user's total positions)
     *      - Creates a new Position struct with the provided data
     *      - Adds the position to the user's position list
     * 
     * @param _newPositionData Array of encoded position parameters (market, collateral, sizes, prices, etc.)
     * @param _positionType Type identifier for the position (e.g., 0 for market neutral)
     * @param _user Address of the user for whom the position is being created
     * 
     * @custom:require Only callable by protocol contracts or registered proxies
     * 
     * @dev The position is created with:
     *      - Position type: `_positionType`
     *      - Position ID: `user.totalPositions + 1`
     *      - PNL: 0 (initialized)
     *      - Active status: true (position starts as active)
     *      - Position data: `_newPositionData`
     */
    function initializeHoldingPosition(ProtocolStorage protocolStorage, bytes[] memory _newPositionData, uint128 _positionType, address _user) external onlyProtocol {
        protocolStorage.updateUserTransactionCount(_user, 1);        
        uint256 positionId = protocolStorage.getUser(_user).totalPositions + 1;
        protocolStorage.addPositionToUser(_user, ProtocolLib.Position(_positionType, positionId, 0, true, _newPositionData));
    }

     /**
     * @notice Modifies a specific field in a user's position data
     * @dev Calls the ProtocolStorage contract to update the given position and field with the new value.
     *      Only callable by protocol contracts or registered protocol proxies.
     *
     * @param _positionId The ID of the position to update
     * @param _positionField The index of the field within the positionData array to modify
     * @param _value The new value (encoded as bytes) to set for the field
     * @param _user Address of the user whose position is being updated
     */
    function managePosition(uint256 _positionId, uint256 _positionField, bytes memory _value, address _user) external onlyProtocol { 
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        protocolStorage.updateUserPositionData(_user, _positionId, _positionField, _value);
    }

    /// @notice Thrown when a function is called by an unauthorized address (not a protocol contract or proxy)
    error SenderNotAllowed();

}