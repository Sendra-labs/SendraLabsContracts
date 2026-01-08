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

import { PairTradingProxy } from "./proxy.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { Roles } from "../../../security/Roles.sol";

/**
 * @title ProxyFactory
 * @notice Factory contract for creating PairTradingProxy instances
 * @dev This contract is responsible for deploying new proxy instances for users.
 *      Only the ProxyManager contract is authorized to deploy proxies through this factory.
 *      Each proxy instance is assigned a unique ID and is owned by a specific user.
 * 
 *      The factory pattern allows for:
 *      - Centralized proxy deployment logic
 *      - Access control through ProxyManager
 *      - Efficient proxy creation with unique IDs
 */
contract ProxyFactory {

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    /**
     * @notice Constructs the ProxyFactory contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }
    
    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    /**
     * @notice Deploys a new PairTradingProxy instance
     * @dev Creates a new proxy with the specified ID and returns its address.
     *      The proxy is initialized with the AddressProvider and the given ID.
     *      This function is restricted to ProxyManager only to ensure proper
     *      registration and ownership tracking.
     * 
     * @param _id Unique identifier for the new proxy instance (assigned by ProxyManager)
     * 
     * @return address The address of the newly deployed PairTradingProxy contract
     * 
     * @custom:require Only callable by ProxyManager contract
     * @custom:revert SenderNotAllowed If called by any address other than ProxyManager
     * 
     * @dev The deployed proxy will be owned by the user registered in ProxyManager for this ID
     */
    function deploy(uint256 _id) external onlyProtocol returns (address){
        address manager = addressProvider.getAddress("ProxyManager");
        if(msg.sender != address(manager)) revert SenderNotAllowed();
        PairTradingProxy proxy = new PairTradingProxy(address(addressProvider), _id);
        return address(proxy);
    }

    /// @notice Thrown when a function is called by an unauthorized address (not ProxyManager)
    error SenderNotAllowed();
}