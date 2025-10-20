//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AddressProvider
 * @dev Centralized contract to manage addresses of all protocols
 * 
 * Scalable solution that allows:
 * - Adding new protocols without touching proxies
 * - Changing implementations without redeploying
 * - Fixed known storage in all proxies
 */
contract AddressProvider {

    Roles public immutable roles;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier onlyAdmin {
        require(roles.isAdmin(msg.sender), "Only admin can call this function");
        _;
    }

    /// @notice Mapping of protocol names to their addresses
    /// @dev Format: "GMX" -> 0x..., "Uniswap" -> 0x..., etc.
    mapping(string => address) public addressMap;
    
    /**
     * @notice Gets the address of a protocol by name
     * @param contractName Protocol name (e.g., "GMX", "Uniswap", "Aave")
     * @return Address of the protocol contract
     */
    function getAddress(string calldata contractName) public view returns (address) {
        return addressMap[contractName];
    }

    /**
     * @notice Sets the address of a protocol
     * @param contractName Protocol name
     * @param _address Address of the protocol contract
     */
    function setAddress(string calldata contractName, address _address) public onlyAdmin {
        addressMap[contractName] = _address;
        emit ContractAddressUpdated(contractName, _address);
    }

    event ContractAddressUpdated(string indexed contractName, address indexed address);

}