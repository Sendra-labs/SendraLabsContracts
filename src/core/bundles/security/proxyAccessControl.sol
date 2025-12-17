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

import { Roles } from "../../../security/Roles.sol";

/**
 * @title ProxyAccessControl
 * @notice Access control contract for managing protocol proxy registration and verification
 * @dev This contract maintains a registry of proxy contracts that are authorized to interact
 *      with the protocol. Only registered protocol contracts can add proxies to the registry.
 * 
 *      Key features:
 *      - Centralized proxy registry for access control
 *      - Protocol contract-only registration
 *      - Query functionality to verify proxy status
 * 
 *      This is used by contracts like PositionInitializer to verify that callers are
 *      either protocol contracts or registered protocol proxies.
 */
contract ProxyAccessControl {
    /// @notice Roles contract for protocol contract verification
    Roles public roles;

    /**
     * @notice Constructs the ProxyAccessControl contract
     * @param _roles Address of the Roles contract
     */
    constructor(address _roles) {
        roles = Roles(_roles);
    }

    /**
     * @notice Modifier to restrict access to protocol contracts only
     * @dev Verifies that the caller is a registered protocol contract via Roles
     * @custom:revert SenderNotAllowed If the caller is not a protocol contract
     */
    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    /// @notice Mapping to track which addresses are registered as protocol proxies
    /// @dev true if the address is a registered proxy, false otherwise
    mapping(address => bool) public isProxy;

    /**
     * @notice Registers a contract as a protocol proxy
     * @dev Adds the specified contract address to the proxy registry, allowing it
     *      to be recognized as an authorized protocol proxy. This is typically called
     *      by ProxyManager when a new proxy is deployed.
     * 
     * @param _contract Address of the proxy contract to register
     * 
     * @custom:require Only callable by protocol contracts
     * @custom:revert SenderNotAllowed If called by a non-protocol contract
     */
    function setIsProtocolProxy(address _contract) public onlyProtocol {
        isProxy[_contract] = true;
    }

    /**
     * @notice Checks if an address is a registered protocol proxy
     * @dev Used by other protocol contracts to verify proxy status for access control
     * 
     * @param _contract Address to check
     * @return true if the address is a registered protocol proxy, false otherwise
     */
    function isProtocolProxy(address _contract) public view returns (bool) {
        return isProxy[_contract];
    }

    /// @notice Thrown when a function is called by an unauthorized address (not a protocol contract)
    error SenderNotAllowed();
}