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

import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { ProxyAccessControl } from "../security/proxyAccessControl.sol";

/**
 * @title PositionInitializer
 * @notice Contract responsible for initializing new positions in the protocol storage
 * @dev This contract handles the creation and initialization of new positions for users.
 *      It manages position IDs, transaction counts, and position data storage.
 *      Access is restricted to protocol contracts and registered protocol proxies.
 */
contract PositionInitializer {

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /// @notice Roles contract for access control verification
    Roles public immutable roles;

    /**
     * @notice Constructs the PositionInitializer contract
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
    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType, address _user) external onlyProtocol {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        protocolStorage.updateUserTransactionCount(_user, 1);        
        uint256 positionId = protocolStorage.getUser(_user).totalPositions + 1;
        protocolStorage.addPositionToUser(_user, ProtocolLib.Position(_positionType, positionId, 0, true, _newPositionData));
    }

    /// @notice Thrown when a function is called by an unauthorized address (not a protocol contract or proxy)
    error SenderNotAllowed();

}