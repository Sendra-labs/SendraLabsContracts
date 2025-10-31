//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { MarketNeutralStorage } from "./MarketNeutralStorage.sol";
import { ProxyFactory } from "../executors/ProxyFactory.sol";

contract ProxyManager {

    Roles public immutable roles;
    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    struct Proxy {
        address owner;
        address proxy;
    }

    struct Batch {
        uint256 availableCount;
        uint256[] proxyIds;
    }

    uint256 public proxyCount;
    uint256 public batchId;
    uint256 public constant MAX_BATCH_SIZE = 100;

    mapping(uint256 => Proxy) public proxies;
    mapping(uint256 => Batch) public availableProxiesBatch;

    event ProxyDeployed(address indexed owner, address indexed proxy, uint256 indexed proxyId);
    event ProxyClaimed(address indexed user, uint256 indexed proxyId);

    function initializeProxy(address _owner) public returns (address _proxyAddress) {
        (uint256 _proxyId, uint256 _batchId, address proxyAddress, bool isAvailable) = getAvailableProxy();  
        if(!isAvailable) {
            _proxyAddress = deployProxy(_owner);
            return (_proxyAddress);
        } else if (isAvailable) { 
            claimAvailableProxy(_proxyId, _batchId, _owner);
            return (proxyAddress);
        }
    }

    function deployProxy(address _owner) internal returns (address) {
        ProxyFactory factory = ProxyFactory(addressProvider.getAddress("ProxyFactory"));
        address proxy = factory.deploy(proxyCount);
        addProxy(proxy, _owner);
        emit ProxyDeployed(_owner, proxy, proxyCount - 1);
        return proxy;
    }

    // when deployed from factory
    function addProxy(address _proxy, address _owner) internal {
        proxies[proxyCount] = Proxy(_owner, _proxy);
        proxyCount++;
    }

    function claimAvailableProxy(uint256 _proxyId, uint256 _batchId, address _owner) internal {
        if(proxies[_proxyId].owner != address(0)) revert ProxyNotAvailable();
        setOwner(_proxyId, _owner);
        deleteAvailableProxy(_proxyId, _batchId);
        emit ProxyClaimed(_owner, _proxyId);
    }

    function deleteAvailableProxy(uint256 _proxyId, uint256 _batchId) internal {
        availableProxiesBatch[_batchId].availableCount--;
        uint256 len = availableProxiesBatch[_batchId].proxyIds.length;
        if(availableProxiesBatch[_batchId].proxyIds[len - 1] != _proxyId) revert InvalidProxyId();
        availableProxiesBatch[_batchId].proxyIds.pop();
    }

    // sets another user as owner of the proxy, used for access control (onlyOwner) in each proxy
    function setOwner(uint256 _proxyId, address _newOwner) internal {
        proxies[_proxyId].owner = _newOwner;
    }

    // when proxy is not managing any position in GMX, it is available for another user to use it
    function setAvailable(uint256 _proxyId) public {
        if(msg.sender != proxies[_proxyId].proxy) revert SenderNotAllowed();
        bool isAdded = false;
        if(checkProxyOwnerPendingOrders(_proxyId)) revert ProxyHasPendingOrders();
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

    function getOwner(uint256 _proxyId) external view returns (address) {
        return proxies[_proxyId].owner;
    }

    // if true, the proxy is not available for another user to use it yet. Must wait for the pending orders to be executed.
    function checkProxyOwnerPendingOrders(uint256 _proxyId) public view returns (bool) {
        MarketNeutralStorage marketNeutralStorage = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage"));
        bytes32[] memory pendingOrderKeys = marketNeutralStorage.getUserPendingOrderKeys(proxies[_proxyId].owner);
        if(pendingOrderKeys.length > 0) return true;
        return false;
    }

    // check if batch is filled, if it is filled a new batch must be created or checked
    function isbatchFilled(uint256 _batchId) public view returns (bool) {
        return availableProxiesBatch[_batchId].availableCount == MAX_BATCH_SIZE;
    }

    // returns the ID of an available proxy, if no proxy is available, it returns 0 and false; if False is returned a new proxy must be deployed
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

    error SenderNotAllowed();
    error ProxyNotAvailable();
    error InvalidProxyId();
    error ProxyHasPendingOrders();

}

/*
Flow: 
1. mainReader calls getAvailableProxy():
    - if no proxy is available, it returns 0 and false -> calls factory to deploy a new proxy
        - factory deploys a new proxy and calls addProxy()
        - proxyManager sets the owner of the proxy
        - this new registered proxy is going to be used by the user to open a position in GMX (proxy not available for another user)
        - when the position is closed and not managing any position in GMX, the proxy is set as available for another user to use it:
            - when closeMarketNeutralDelegatecall or another function that closes a position is called, the proxy is set as available for another user to use it
                the proxy must call setAvailable with its ID or maybe better is the contract callback afterorderexecution
                - this is done to avoid having to deploy contracts that will have a short life cycle. so we make them reusable.

    - if a proxy is available, it returns the ID of the proxy and true.
        - frontend makes a call using user as msg.sender to the address of the available ID to one of the open Position functions


        ___________________________

        PARA MAÑANA:
        - el proxy debe controlar si puede meter mas posiciones o no;
        - debemos meter el proxyId en la data de la posicion. La posicion la
                       sabemos en storage de user y de ahi sacamos el proxyId.
        - vamos a hacerlo all de una, una sola funcion que en una txs llama a ver si hay disponible,
              si hay disponible, lo claimea para el owner que lo pide, si no lo despliega.
        - proxy debe llamar a una funcion para borrarse de los availables cunado se use/claimee
*/