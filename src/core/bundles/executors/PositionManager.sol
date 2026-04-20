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

import { SendraStorage } from "../../../core/SendraStorage.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { ProxyAccessControl } from "../security/proxyAccessControl.sol";

/**
 * @title PositionManager
 * @notice Contract responsible for initializing new positions in the protocol storage
 * @dev This contract handles the creation and initialization of new positions for users.
 *      It manages position IDs, transaction counts, and position data storage.
 *      Access is restricted to protocol contracts and registered protocol proxies.
 */
contract PositionManager {

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /// @notice Roles contract for access control verification
    Roles public immutable roles;

    /**
     * @notice Constructs the PositionManager contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    /**
     * @notice Modifier to restrict access to protocol contracts and registered proxies only
     * @dev Checks if the caller is either:
     *      1. A registered protocol contract (via Roles)
     *      2. A registered protocol proxy (via ProxyAccessControl)
     * @custom:revert SenderNotAllowed If the caller is not authorized
     */
    modifier onlyProtocol() {
        if(
            !roles.isProtocolContract(msg.sender)
            && !ProxyAccessControl(addressProvider.getAddress("ProxyAccessControl")).isProtocolProxy(msg.sender)
        ) 
        revert SenderNotAllowed();
        _;
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
        SendraStorage sendraStorage = SendraStorage(addressProvider.getAddress("SendraStorage"));
        sendraStorage.updateUserPositionData(_user, _positionId, _positionField, _value);
    }

    /// @notice Thrown when a function is called by an unauthorized address (not a protocol contract or proxy)
    error SenderNotAllowed();

}