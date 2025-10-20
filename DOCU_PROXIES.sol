// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title UniversalProxy
 * @dev Generic proxy that allows delegatecall to any implementation
 * 
 * This contract solves GMX's problem where all positions are grouped under
 * a single address. Each user has their own proxy with a unique address,
 * enabling separate positions in GMX.
 * 
 * Architecture:
 * - User → Proxy → delegatecall → Implementation → GMX
 * - msg.sender in GMX = proxy address (unique per user)
 * - Known storage: only Addresses contract for scalability
 */
contract userProxy {
    /// @notice Centralized contract that maintains all protocol addresses
    /// @dev Enables scalability without changing proxy storage
    Addresses public addresses;
    
    /**
     * @notice Proxy constructor
     * @param _addresses Address of the Addresses contract containing all protocol addresses
     */
    constructor(address _addresses) {
        addresses = Addresses(_addresses);
    }
    
    /**
     * @notice Executes delegatecall to any implementation
     * @dev Preserves original msg.sender and executes code in proxy context
     * @param target Address of the implementation contract to execute
     */
    function delegatecall(address target) public {
        (bool success,) = target.delegatecall(
            abi.encodeWithSignature("test()")
        );
        require(success, "Delegate call failed");
    }
}

/**
 * @title Addresses
 * @dev Centralized contract to manage addresses of all protocols
 * 
 * Scalable solution that allows:
 * - Adding new protocols without touching proxies
 * - Changing implementations without redeploying
 * - Fixed known storage in all proxies
 */
contract Addresses {
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
    function setAddress(string calldata contractName, address _address) public {
        addressMap[contractName] = _address;
    }
}

/**
 * @title MarketNeutral
 * @dev Implementation that executes GMX operations using dynamic addresses
 * 
 * This contract executes via delegatecall from the user's proxy.
 * Gets protocol addresses dynamically from the Addresses contract,
 * enabling scalability without storage changes.
 */
contract marketNeutral {
    /// @notice Reference to Addresses contract to get addresses dynamically
    Addresses public addresses;
    
    /**
     * @notice Implementation constructor
     * @param _addresses Address of the Addresses contract
     */
    constructor(address _addresses) {
        addresses = Addresses(_addresses);
    }
    
    /// @notice Event emitted when an operation is executed
    /// @param msgSender Address that initiated the call (original user)
    /// @param thisAddress Address of the proxy that executes (unique per user)
    event TestCalled(address msgSender, address thisAddress);

    /**
     * @notice Example function that interacts with GMX
     * @dev Gets GMX address dynamically and executes operation
     * 
     * Flow:
     * 1. Gets GMX address from Addresses
     * 2. Calls GMX function
     * 3. GMX sees msg.sender = proxy address (unique per user)
     * 4. Result: separate positions in GMX per user
     */
    function test() public {
        // Gets GMX address dynamically (scalable)
        GMX(addresses.getAddress("GMX")).gmx();
        
        // Emits event with delegatecall context
        emit TestCalled(msg.sender, address(this));
    }
}

/**
 * @title GMX
 * @dev Mock contract that simulates GMX for testing
 * 
 * In the real implementation, this would be the actual GMX contract.
 * Demonstrates how GMX sees msg.sender as the user's proxy address.
 */
contract GMX {
    /// @notice Counter of executed operations
    uint256 public count;
    
    /// @notice Last address that called a GMX function
    /// @dev In real GMX, this determines which position the operation is assigned to
    address public sender;
    
    /**
     * @notice Mock function that simulates GMX operation
     * @dev Increments counter and saves msg.sender (should be proxy address)
     */
    function gmx() public {
        count++;
        sender = msg.sender; // ← This will be the user's proxy address
    }
}