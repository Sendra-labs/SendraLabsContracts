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
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTrading,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }
    
    function setStopLoss(
        PairTradingLib.CloseSidePairTradingInputWithStopLoss calldata _inputLong, 
        PairTradingLib.CloseSidePairTradingInputWithStopLoss calldata _inputShort
    ) public payable onlyOwner nonReentrant {
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTradingWithStopLoss,
                (_inputLong)
            )
        );
        require(success, "Delegatecall failed");
        (bool successShort,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTradingWithStopLoss,
                (_inputShort)
            )
        );
        require(successShort, "Delegatecall failed");
    }

    function setStopLossSidePairTradingDelegatecall(PairTradingLib.CloseSidePairTradingInputWithStopLoss calldata _input) public payable onlyOwner nonReentrant {
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTradingWithStopLoss,
                (_input)
            )
        );
        require(success, "Delegatecall failed");
    }
    
    // create a whitelist instead of a blacklist... a contract with allowed addresses.
    function customFunctionDelegatecall(address _target, bytes memory _data) public onlyOwner nonReentrant {
        address positionInitializer = addressProvider.getAddress("PositionInitializer");
        address pairTradingStorage = addressProvider.getAddress("PairTradingStorage");
        if(_target == positionInitializer || _target == pairTradingStorage) revert TargetNotAllowed();
        (bool success,) = _target.delegatecall(_data);
        require(success, "Delegatecall failed");
    }

    function customFunction(address _target, bytes memory _data) public onlyOwner nonReentrant {
        address positionInitializer = addressProvider.getAddress("PositionInitializer");
        address pairTradingStorage = addressProvider.getAddress("PairTradingStorage");
        if(_target == positionInitializer || _target == pairTradingStorage) revert TargetNotAllowed();
        (bool success,) = _target.call(_data);
        require(success, "Call failed");
    }

    function manualClosePairTradingPositionWithStopLossDelegatecall(PairTradingLib.ManualCloseStopLossPairTradingInput calldata _input) public payable onlyOwner nonReentrant {
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.manualClosePairTradingPositionWithStopLoss,
                (_input, id)
            )
        );
        require(success, "Delegatecall failed");
    }

    function cancelOrder(bytes32 _key) public onlyOwner nonReentrant {
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.cancelOrder,
                (_key, id)
            )
        );
        require(success, "Delegatecall failed");
    }

    function updateStopLoss(bytes32 _key, PairTradingLib.CloseSidePairTradingInputWithStopLoss calldata _input) public onlyOwner nonReentrant {
        cancelOrder(_key);
        (bool success,) = pairTrading.delegatecall(
            abi.encodeCall(
                PairTrading.closeSidePairTradingWithStopLoss,
                (_input)
            )
        );
        require(success, "Delegatecall failed");    }

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
        ProxyManager(addressProvider.getAddress("ProxyManager")).manageMarkets(_marketLong, _marketShort, id);
    }

    /**
     * @notice Returns the unique identifier of this proxy
     * @return The proxy ID assigned during construction
     */
    function getId() public view returns (uint256) {
        return id;
    }
    
    /// @notice Thrown when a function is called by an address that is not the proxy owner
    error NotOwner();
    

    /// @notice Thrown when attempting to call a target that is not allowed
    error TargetNotAllowed();

}