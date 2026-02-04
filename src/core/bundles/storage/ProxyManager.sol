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
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { PairTradingStorage } from "./PairTradingStorage.sol";
import { ProxyFactory } from "../executors/ProxyFactory.sol";
import { PairTradingProxy } from "../executors/proxy.sol";
import { ProxyAccessControl } from "../security/proxyAccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { GMXMarketsRegistry } from "../../../core/config/gmxMarkets.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";

/**
 * @title ProxyManager
 * @notice Manages the lifecycle of PairTradingProxy instances for efficient resource usage
 * @dev This contract implements a proxy pool system to minimize gas costs by reusing proxy contracts.
 *      Proxies are pooled when they become available (no active positions) and can be claimed by
 *      new users. If no proxies are available, new ones are deployed through ProxyFactory.
 * 
 *      Key features:
 *      - Proxy deployment and registration
 *      - Proxy pooling and availability management
 *      - Batch-based proxy tracking for gas efficiency
 *      - Owner management and access control
 * 
 *      Flow:
 *      1. User requests a proxy via initializeProxy()
 *      2. System checks for available proxies in batches
 *      3. If available: proxy is claimed and owner is set
 *      4. If not available: new proxy is deployed
 *      5. When position closes: proxy is marked as available for reuse
 */
contract ProxyManager is ReentrancyGuard {

    /// @notice Roles contract for access control verification
    Roles public immutable roles;
    
    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;

    /**
     * @notice Constructs the ProxyManager contract
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
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

    modifier onlyProxy(address _proxy) {
        if(!ProxyAccessControl(addressProvider.getAddress("ProxyAccessControl")).isProtocolProxy(_proxy)) revert SenderNotAllowed();
        _;
    }

    /**
     * @notice Structure representing a proxy and its owner
     * @param owner Address of the current owner (address(0) if available)
     * @param proxy Address of the PairTradingProxy contract
     */
    struct Proxy {
        address owner;
        address proxy;
    }

    /**
     * @notice Structure representing a batch of available proxies
     * @param availableCount Number of available proxies in this batch
     * @param proxyIds Array of proxy IDs that are available in this batch
     */
    struct Batch {
        uint256 availableCount;
        uint256[] proxyIds;
    }

    /// @notice Total number of proxies ever deployed (increments, never decreases)
    uint256 public proxyCount;
    
    /// @notice Current batch ID (increments as batches fill up)
    uint256 public batchId;
    
    /// @notice Maximum number of proxies per batch (for gas efficiency)
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice Mapping from proxy ID to Proxy struct
    mapping(uint256 => Proxy) public proxies;
    
    /// @notice Mapping from batch ID to Batch struct containing available proxies
    mapping(uint256 => Batch) public availableProxiesBatch;

    /// @notice Markets in use per proxy (long + short addresses). Cleared when position closes.
    mapping(uint256 => address[]) public proxyMarkets;


    // Events

    /**
     * @notice Emitted when a new proxy is deployed
     * @param owner Address of the owner assigned to the proxy
     * @param proxy Address of the deployed proxy contract
     * @param proxyId The unique ID assigned to the proxy
     */
    event ProxyDeployed(address indexed owner, address indexed proxy, uint256 indexed proxyId);
    
    /**
     * @notice Emitted when a user claims an available proxy
     * @param user Address of the user claiming the proxy
     * @param proxyId The ID of the claimed proxy
     */
    event ProxyClaimed(address indexed user, uint256 indexed proxyId);

    /**
     * @notice Initializes a proxy for a user (deploys new or claims available)
     * @dev Main entry point for obtaining a proxy. Checks for available proxies first,
     *      and if none are available, deploys a new one. Implements reentrancy protection.
     * 
     * @param _owner Address of the user who will own the proxy
     * @return _proxyAddress Address of the proxy assigned to the user
     * 
     * @dev Flow:
     *      1. Calls getAvailableProxy() to check for available proxies
     *      2. If available: claims it and sets owner
     *      3. If not available: deploys new proxy via ProxyFactory
     */
    function initializeProxy(address _owner) public nonReentrant returns (address _proxyAddress) {
        (uint256 _proxyId, uint256 _batchId, address proxyAddress, bool isAvailable) = getAvailableProxy();  
        if(!isAvailable) {
            _proxyAddress = deployProxy(_owner);
            return (_proxyAddress);
        } else if (isAvailable) { 
            claimAvailableProxy(_proxyId, _batchId, _owner);
            return (proxyAddress);
        }
    }

    /**
     * @notice Deploys a new proxy through ProxyFactory
     * @dev Creates a new proxy, registers it, and assigns ownership
     * @param _owner Address of the user who will own the proxy
     * @return Address of the newly deployed proxy
     */
    function deployProxy(address _owner) internal returns (address) {
        ProxyFactory factory = ProxyFactory(addressProvider.getAddress("ProxyFactory"));
        address proxy = factory.deploy(proxyCount);
        addProxy(proxy, _owner);
        emit ProxyDeployed(_owner, proxy, proxyCount - 1);
        return proxy;
    }

    /**
     * @notice Registers a newly deployed proxy in the system
     * @dev Stores proxy information, registers it with ProxyAccessControl, and increments proxyCount
     * @param _proxy Address of the proxy contract to register
     * @param _owner Address of the initial owner
     */
    function addProxy(address _proxy, address _owner) internal {
        proxies[proxyCount] = Proxy(_owner, _proxy);
        ProxyAccessControl(addressProvider.getAddress("ProxyAccessControl")).setIsProtocolProxy(_proxy);
        proxyCount++;
    }

    /**
     * @notice Claims an available proxy and assigns it to a new owner
     * @dev Verifies proxy is available, sets owner, and removes from available batch
     * @param _proxyId ID of the proxy to claim
     * @param _batchId ID of the batch containing this proxy
     * @param _owner Address of the new owner
     * @custom:revert ProxyNotAvailable If the proxy already has an owner
     */
    function claimAvailableProxy(uint256 _proxyId, uint256 _batchId, address _owner) internal {
        if(proxies[_proxyId].owner != address(0)) revert ProxyNotAvailable();
        setOwner(_proxyId, _owner);
        deleteAvailableProxy(_proxyId, _batchId);
        emit ProxyClaimed(_owner, _proxyId);
    }

    /**
     * @notice Removes a proxy from the available batch
     * @dev Uses swap-and-pop pattern for efficient removal from batch array
     * @param _proxyId ID of the proxy to remove
     * @param _batchId ID of the batch containing this proxy
     * @custom:revert InvalidProxyId If the proxy ID doesn't match the last element (swap-and-pop requirement)
     */
    function deleteAvailableProxy(uint256 _proxyId, uint256 _batchId) internal {
        availableProxiesBatch[_batchId].availableCount--;
        uint256 len = availableProxiesBatch[_batchId].proxyIds.length;
        if(availableProxiesBatch[_batchId].proxyIds[len - 1] != _proxyId) revert InvalidProxyId();
        availableProxiesBatch[_batchId].proxyIds.pop();
    }

    /**
     * @notice Sets the owner of a proxy (used for access control in proxy's onlyOwner modifier)
     * @dev Updates the owner in the Proxy struct. Owner of address(0) means proxy is available.
     * @param _proxyId ID of the proxy
     * @param _newOwner Address of the new owner (address(0) to mark as available)
     */
    function setOwner(uint256 _proxyId, address _newOwner) internal {
        proxies[_proxyId].owner = _newOwner;
    }

    /**
     * @notice Marks a proxy as available for reuse when it has no active positions
     * @dev Called by ClosePositionCallbacks when all positions are closed.
     *      Adds proxy to an available batch (or creates new batch if all are full).
     *      Sets owner to address(0) to mark as available.
     * 
     * @param _proxyId ID of the proxy to mark as available
     * 
     * @custom:require Only callable by protocol contracts
     * @custom:require Proxy must have an owner and be available (no active positions)
     * 
     * @dev Batch logic:
     *      - Searches for first non-full batch
     *      - If found: adds proxy to that batch
     *      - If all batches full: creates new batch with this proxy
     */
    function setAvailable(uint256 _proxyId) public onlyProtocol {
        bool isAdded = false;
        bool isAvailable = isAvailable(_proxyId);
        if(getOwner(_proxyId) != address(0)) {
            if(isAvailable) {
                for(uint256 i = 0; i < batchId + 1; i++) {
                    if(!isbatchFilled(i)) {
                        availableProxiesBatch[i].availableCount++;
                        availableProxiesBatch[i].proxyIds.push(_proxyId);
                        isAdded = true;
                        break;
                    }
                }
                if(!isAdded) {
                    batchId++;
                    uint256[] memory proxyIds = new uint256[](1);
                    proxyIds[0] = _proxyId;
                    availableProxiesBatch[batchId] = Batch(1, proxyIds);
                }
                setOwner(_proxyId, address(0));
            }
        }
    }

    /**
     * @notice Validates and adds markets to the tracking array
     * @dev Checks if either market is already in use by this proxy before adding them.
     *      Prevents conflicts by ensuring only one position per market pair per proxy.
     * 
     * @param _marketLong Market identifier for the long position
     * @param _marketShort Market identifier for the short position
     * 
     * @custom:revert MarketAlreadyExists If either marketLong or marketShort is already in the markets array
     */
    function manageMarkets(string calldata _marketLong, string calldata _marketShort, uint256 _proxyId) external onlyProxy(msg.sender) {
        address proxy = proxies[_proxyId].proxy;
        if(proxy != msg.sender) revert SenderNotAllowed();
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < proxyMarkets[_proxyId].length; i++) {
            if (
                proxyMarkets[_proxyId][i] == marketLong || 
                proxyMarkets[_proxyId][i] == marketShort
            ) {
                revert MarketAlreadyExists();
            }
        }
        proxyMarkets[_proxyId].push(marketLong);
        proxyMarkets[_proxyId].push(marketShort);
    }

    /**
     * @notice Removes one market (long or short) from a proxy's list when a position side is closed.
     * @dev Uses swap-and-pop for O(1) removal. Only removes first occurrence; call once per callback (one side).
     * @param _isLong true = remove long market (positionData[2]), false = short (positionData[3])
     * @param _positionId Position ID to read market from
     * @param _proxyId Proxy ID whose proxyMarkets to update
     * @param _owner Position owner (receiver) to load position from ProtocolStorage
     */
    function deleteMarket(bool _isLong, uint256 _positionId, uint256 _proxyId, address _owner) external onlyProtocol {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_owner, _positionId);
        address market = _isLong ? abi.decode(position.positionData[2], (address)) : abi.decode(position.positionData[3], (address));
        for(uint256 i = proxyMarkets[_proxyId].length; i > 0; i--) {
            uint256 index = i - 1;
            if (proxyMarkets[_proxyId][index] == market) {
                proxyMarkets[_proxyId][index] = proxyMarkets[_proxyId][proxyMarkets[_proxyId].length - 1];
                proxyMarkets[_proxyId].pop();
                return;
            }
        }
        revert MarketNotFound();
    }

    function isAvailable(uint256 _proxyId) public view returns (bool) {
        return proxyMarkets[_proxyId].length == 0;
    }

    /**
     * @notice Checks if the specified markets are currently being used by this proxy
     * @dev Used to verify market availability before opening new positions
     * 
     * @param _marketLong Market identifier for the long position
     * @param _marketShort Market identifier for the short position
     * 
     * @return true if either market is currently in use, false otherwise
     */
    function isMarketBeingUsed(string calldata _marketLong, string calldata _marketShort, uint256 _proxyId) public view returns (bool) {
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < proxyMarkets[_proxyId].length; i++) {
            if (proxyMarkets[_proxyId][i] == marketLong || proxyMarkets[_proxyId][i] == marketShort) {
                return true; // market is being used
            }
        }
        return false; // market is not being used
    }


    /**
     * @notice Gets the current owner of a proxy
     * @param _proxyId ID of the proxy
     * @return Address of the owner (address(0) if proxy is available)
     */
    function getOwner(uint256 _proxyId) public view returns (address) {
        return proxies[_proxyId].owner;
    }

    /**
     * @notice Gets the available count of proxies in a batch
     * @param _batchId ID of the batch to check
     * @return The number of available proxies in the batch
     */
    function getBatchAvailableCount(uint256 _batchId) public view returns (uint256) {
        return availableProxiesBatch[_batchId].availableCount;
    }

    /**
     * @notice Checks if a batch is filled to capacity
     * @dev Used to determine if a new batch should be created
     * @param _batchId ID of the batch to check
     * @return true if the batch has reached MAX_BATCH_SIZE, false otherwise
     */
    function isbatchFilled(uint256 _batchId) public view returns (bool) {
        return availableProxiesBatch[_batchId].availableCount == MAX_BATCH_SIZE;
    }

    /**
     * @notice Gets the first available proxy from any batch
     * @dev Searches through all batches (newest first) to find an available proxy.
     *      Returns the last proxy in the first batch with available proxies (LIFO).
     * 
     * @return proxyId ID of the available proxy (0 if none available)
     * @return batchId ID of the batch containing the proxy (0 if none available)
     * @return proxyAddress Address of the proxy contract (address(0) if none available)
     * @return isAvailable true if a proxy is available, false if new proxy must be deployed
     * 
     * @dev Returns (0, 0, address(0), false) if no proxies are available,
     *      indicating that initializeProxy should deploy a new one
     */
    function getAvailableProxy() public view returns (uint256, uint256, address, bool) { // proxyId, batchId, proxyAddress, isAvailable
        for(uint256 i = 0; i < batchId + 1; i++) {
            uint256 availableCount = availableProxiesBatch[i].availableCount;
            if(availableCount > 0) {
                uint256 _id = availableProxiesBatch[i].proxyIds[availableCount - 1];
                return (_id, i, proxies[_id].proxy, true);
            }
        }
        return (0, 0, address(0), false); // needs to call factory to deploy a new proxy
    }

    /// @notice Thrown when a function is called by an unauthorized address (not a protocol contract)
    error SenderNotAllowed();
    
    /// @notice Thrown when attempting to claim a proxy that is not available (already has an owner)
    error ProxyNotAvailable();
    
    /// @notice Thrown when proxy ID validation fails during batch operations
    error InvalidProxyId();
    
    /// @notice Thrown when attempting to perform an operation on a proxy with pending orders
    error ProxyHasPendingOrders();
    
    /// @notice Thrown when attempting to remove a market that is not in use
    error MarketNotFound();

    /// @notice Thrown when attempting to use a market that is already in use by this proxy
    error MarketAlreadyExists();

}