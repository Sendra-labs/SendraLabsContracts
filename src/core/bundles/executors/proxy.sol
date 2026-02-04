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

import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PairTradingLib } from "../../../lib/PairTrading/PairTradingLib.sol";
import { GMXMarketsRegistry } from "../../config/gmxMarkets.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProxyManager } from "../storage/ProxyManager.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { PairTrading } from "./PairTrading.sol";

/**
 * @title PairTradingProxy
 * @notice Proxy contract for executing market neutral trading strategies on GMX
 * @dev This contract acts as a proxy that delegates calls to the PairTrading implementation.
 *      Each proxy instance is owned by a single user and manages their market neutral positions.
 *      The proxy tracks which markets are currently in use and ensures only one position per market pair.
 * 
 *      Key features:
 *      - Owner-restricted access for all operations
 *      - Delegatecall pattern for upgradable implementation
 *      - Market tracking to prevent conflicts
 *      - Reentrancy protection on all state-changing operations
 */
contract PairTradingProxy is ReentrancyGuard {

    /// @notice Address provider that stores all protocol addresses
    AddressProvider public immutable addressProvider;
    
    /// @notice Address of the PairTrading implementation contract (can be updated)
    address public pairTrading;
    
    /// @notice Unique identifier for this proxy instance
    uint256 public immutable id;

    /**
     * @notice Constructs a new PairTradingProxy instance
     * @param _addressProvider Address of the AddressProvider contract
     * @param _id Unique identifier for this proxy (assigned by ProxyManager)
     */
    constructor(address _addressProvider, uint256 _id) {
        addressProvider = AddressProvider(_addressProvider);
        id = _id;
        pairTrading = addressProvider.getAddress("PairTrading");
    }

    /**
     * @notice Modifier to restrict access to the proxy owner only
     * @dev Retrieves the owner from ProxyManager and verifies the caller matches
     * @custom:revert NotOwner If the caller is not the registered owner of this proxy
     */
    modifier onlyOwner() {
        address owner = ProxyManager(addressProvider.getAddress("ProxyManager")).getOwner(id);
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Internal array tracking which markets are currently being used by this proxy
    address[] internal markets;

    /**
     * @notice Updates the PairTrading implementation address
     * @dev Allows the proxy owner to update the implementation contract address,
     *      useful for upgrades or bug fixes
     * @custom:require Only callable by the proxy owner
     */
    function initialize() public onlyOwner {
        pairTrading = addressProvider.getAddress("PairTrading");
    }

    /**
     * @notice Opens a market neutral position using ETH as collateral
     * @dev Delegates the call to PairTrading.openEtherPairTrading via delegatecall.
     *      Before executing, validates and tracks the markets to prevent conflicts.
     * 
     * @param _input Input parameters for opening the market neutral position:
     *        - totalEthAmount: Total ETH to be divided between long and short
     *        - marketLong: Market identifier for the long position
     *        - marketShort: Market identifier for the short position
     *        - sizeDeltaUsdLong: Size of long position in USD
     *        - sizeDeltaUsdShort: Size of short position in USD
     *        - slippageBps: Allowed slippage in basis points
     *        - executionFee: Execution fee for GMX orders
     * 
     * @custom:require Only callable by the proxy owner
     * @custom:require msg.value must cover totalEthAmount + executionFee * 2
     * @custom:revert MarketAlreadyExists If either market is already in use by this proxy
     * @custom:revert "Delegatecall failed" If the delegatecall to PairTrading fails
     */
    function openEtherPairTradingDelegatecall(PairTradingLib.EtherPairTradingInput calldata _input) public payable onlyOwner nonReentrant {
        manageMarkets(_input.marketLong, _input.marketShort);
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.openEtherPairTrading,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }

    /**
     * @notice Opens a market neutral position using USDC as collateral
     * @dev Delegates the call to PairTrading.openUSDCPairTrading via delegatecall.
     *      Before executing, validates and tracks the markets to prevent conflicts.
     * 
     * @param _input Input parameters for opening the market neutral position:
     *        - totalUsdcAmount: Total USDC to be divided between long and short
     *        - marketLong: Market identifier for the long position
     *        - marketShort: Market identifier for the short position
     *        - sizeDeltaUsdLong: Size of long position in USD
     *        - sizeDeltaUsdShort: Size of short position in USD
     *        - slippageBps: Allowed slippage in basis points
     *        - executionFee: Execution fee for GMX orders
     * 
     * @custom:require Only callable by the proxy owner
     * @custom:require User must have approved this contract to spend totalUsdcAmount USDC
     * @custom:require msg.value must cover executionFee * 2
     * @custom:revert MarketAlreadyExists If either market is already in use by this proxy
     * @custom:revert "Delegatecall failed" If the delegatecall to PairTrading fails
     */
    function openUSDCPairTradingDelegatecall(PairTradingLib.UsdcPairTradingInput calldata _input) public payable onlyOwner nonReentrant {
        manageMarkets(_input.marketLong, _input.marketShort);
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.openUSDCPairTrading,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }

    /**
     * @notice Closes both sides of a market neutral position simultaneously
     * @dev Delegates the call to PairTrading.closePairTrading via delegatecall.
     *      After execution, removes the markets from tracking.
     * 
     * @param _input Input parameters for closing the position:
     *        - positionId: ID of the market neutral position to close
     *        - executionFee: Total execution fee to be split between both orders
     *        - slippageBps: Allowed slippage in basis points for closing
     * 
     * @custom:require Only callable by the proxy owner
     * @custom:require msg.value must cover executionFee
     * @custom:revert "Delegatecall failed" If the delegatecall to PairTrading fails
     */
    function closePairTradingDelegatecall(PairTradingLib.ClosePairTradingInput calldata _input) public payable onlyOwner nonReentrant {
        deleteMarket(_input.positionId);
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closePairTrading,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }

    /**
     * @notice Closes one side (long or short) of a market neutral position
     * @dev Delegates the call to PairTrading.closeSidePairTrading via delegatecall.
     *      After execution, removes the markets from tracking when both sides are closed.
     * 
     * @param _input Input parameters for closing one side:
     *        - positionId: ID of the market neutral position
     *        - executionFee: Execution fee for the GMX order
     *        - slippageBps: Allowed slippage in basis points
     *        - value: ETH value to send for execution fee
     *        - isLongSide: Whether to close the long (true) or short (false) side
     * 
     * @custom:require Only callable by the proxy owner
     * @custom:require msg.value must cover executionFee
     * @custom:revert "Delegatecall failed" If the delegatecall to PairTrading fails
     */
    function closeSidePairTradingDelegatecall(PairTradingLib.CloseSidePairTradingInput calldata _input) public payable onlyOwner nonReentrant {
        deleteMarket(_input.positionId);
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTrading,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }

    
    // crear whitelist en vez de blacklist... un contrato con address permitidas.
    function customFunctionDelegatecall(address _target, bytes memory _data) public onlyOwner nonReentrant {
        address positionInitializer = addressProvider.getAddress("PositionInitializer");
        address pairTradingStorage = addressProvider.getAddress("PairTradingStorage");
        if(_target == positionInitializer || _target == pairTradingStorage) revert TragetNotAllowed();
        (bool success,) = _target.delegatecall(_data);
        require(success, "Delegatecall failed");
    }

    function customFunction(address _target, bytes memory _data) public onlyOwner nonReentrant {
        address positionInitializer = addressProvider.getAddress("PositionInitializer");
        address pairTradingStorage = addressProvider.getAddress("PairTradingStorage");
        if(_target == positionInitializer || _target == pairTradingStorage) revert TragetNotAllowed();
        (bool success,) = _target.call(_data);
        require(success, "Call failed");
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
    function manageMarkets(string calldata _marketLong, string calldata _marketShort) internal {
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < markets.length; i++) {
            if (
                markets[i] == marketLong || 
                markets[i] == marketShort
            ) {
                revert MarketAlreadyExists();
            }
        }
        markets.push(marketLong);
        markets.push(marketShort);
    }

    /**
     * @notice Removes markets from tracking when a position is closed
     * @dev Retrieves the position data, extracts market addresses, and removes them
     *      from the markets array. Uses swap-and-pop pattern for efficient deletion.
     * 
     * @param _positionId ID of the position being closed
     */
    function deleteMarket(uint256 _positionId) internal {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        address owner = ProxyManager(addressProvider.getAddress("ProxyManager")).getOwner(id);
        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(owner, _positionId);
        address marketLong = abi.decode(position.positionData[2], (address));
        address marketShort = abi.decode(position.positionData[3], (address));
        for(uint256 i = markets.length; i > 0; i--) {
            uint256 index = i - 1;
            if (markets[index] == marketLong || markets[index] == marketShort) {
                markets[index] = markets[markets.length - 1];
                markets.pop();
            }
        }
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
    function isMarketBeingUsed(string calldata _marketLong, string calldata _marketShort) public view returns (bool) {
        GMXMarketsRegistry gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
        address marketLong = gmxMarkets.getMarket(_marketLong);
        address marketShort = gmxMarkets.getMarket(_marketShort);
        for(uint256 i = 0; i < markets.length; i++) {
            if (markets[i] == marketLong || markets[i] == marketShort) {
                return true; // market is being used
            }
        }
        return false; // market is not being used
    }

    /**
     * @notice Returns the unique identifier of this proxy
     * @return The proxy ID assigned during construction
     */
    function getId() public view returns (uint256) {
        return id;
    }

    /**
     * @notice Checks if this proxy is available (not currently managing any positions)
     * @dev A proxy is available when the markets array is empty, meaning no active positions
     * 
     * @return true if no markets are tracked (proxy is available), false otherwise
     */
    function isAvailable() public view returns (bool) {
        return markets.length == 0;
    }
    
    /// @notice Thrown when a function is called by an address that is not the proxy owner
    error NotOwner();
    
    /// @notice Thrown when attempting to use a market that is already in use by this proxy
    error MarketAlreadyExists();

    /// @notice Thrown when attempting to call a target that is not allowed
    error TragetNotAllowed();

}