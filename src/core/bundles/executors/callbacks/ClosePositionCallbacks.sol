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

import { IOrderCallbackReceiver } from "../../../../interfaces/GMX/IOrderCallbackReceiver.sol";
import { IGasFeeCallbackReceiver } from "gmx-synthetics/callback/IGasFeeCallbackReceiver.sol";
import { AddressProvider } from "../../../../core/config/AddressProvider.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EventUtils } from "gmx-synthetics/event/EventUtils.sol";
import { ProtocolStorage } from "../../../../core/ProtocolStorage.sol";
import { PairTradingStorage } from "../../storage/PairTradingStorage.sol";
import { PairTradingLib } from "../../../../lib/PairTrading/PairTradingLib.sol";
import { IWETH } from "../../../../interfaces/IWETH.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolLib } from "../../../../lib/Protocol.lib.sol";
import { Roles } from "../../../../security/Roles.sol";
import { ProxyManager } from "../../storage/ProxyManager.sol";
import { PairTradingProxy } from "../proxy.sol";
import { GMXMarketsRegistry } from "../../../../core/config/gmxMarkets.sol";
import { GMXPrices } from "../../../../periphery/utilsGMX/GMXPrices.sol";

/**
 * @title ClosePositionCallbacks
 * @notice Handles GMX order execution callbacks for closing market neutral positions
 * @dev This contract receives callbacks from GMX OrderHandler when positions are closed
 * @dev Processes execution data, updates position state, transfers funds to users, and manages proxy availability
 */
contract ClosePositionCallbacks is IOrderCallbackReceiver, IGasFeeCallbackReceiver, ReentrancyGuard {
    
    using SafeERC20 for IERC20;
    using EventUtils for EventUtils.AddressItems;
    using EventUtils for EventUtils.UintItems;
    using EventUtils for EventUtils.IntItems;
    using EventUtils for EventUtils.BoolItems;

    /// @notice AddressProvider contract for accessing protocol addresses
    AddressProvider public immutable addressProvider;
    
    /// @notice USDC token address
    address public immutable usdc;
    
    /// @notice WETH token address
    address public immutable weth;
    
    /// @notice GMX Markets Registry contract
    GMXMarketsRegistry public immutable gmxMarkets;
    
    /**
     * @notice Constructor
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        weth = addressProvider.getAddress("WETH");
        usdc = addressProvider.getAddress("USDC");
        gmxMarkets = GMXMarketsRegistry(addressProvider.getAddress("GMXMarkets"));
    }

    /**
     * @notice Modifier to restrict access to GMX OrderHandler only
     * @dev Ensures only GMX OrderHandler can trigger callbacks
     */
    modifier onlyOrderHandler() {
        require(msg.sender == addressProvider.getAddress("OrderHandlerGMX"), "Only order handler");
        _;
    }

    /**
     * @notice Emitted when calculation of position side (long/short) fails
     * @param orderKey The order key that failed
     * @param positionId The position ID associated with the order
     */
    event IsLongSideCalculationFailed(
        bytes32 indexed orderKey,
        uint256 indexed positionId
    );

    /**
     * @notice Emitted when a position side is successfully closed
     * @param receiver Address that receives the funds
     * @param positionId The position ID
     * @param isLongSide Whether the closed side was long
     * @param outputToken Token address received
     * @param outputAmount Amount of tokens received
     */
    event PositionSideClosedSuccess(
        address indexed receiver,
        uint256 indexed positionId,
        bool isLongSide,
        address outputToken,
        uint256 outputAmount
    );

    /**
     * @notice Emitted when execution processing fails
     * @param orderKey The order key that failed
     * @param positionId The position ID
     * @param receiver Address that should receive funds
     * @param reason Error reason
     */
    event ExecutionProcessingFailed(
        bytes32 indexed orderKey,
        uint256 indexed positionId,
        address indexed receiver,
        string reason
    );

    /**
     * @notice Emitted when emergency withdrawal is executed
     * @param admin Address of the admin executing the withdrawal
     * @param token Token address (address(0) for ETH)
     * @param to Destination address
     * @param amount Amount withdrawn
     * @param reason Reason for emergency withdrawal
     * @param timestamp Block timestamp
     */
    event EmergencyWithdraw(
        address indexed admin,
        address indexed token,
        address indexed to,
        uint256 amount,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a position is successfully rescued
     * @param user Address of the user whose position was rescued
     * @param positionId The position ID
     * @param isLongSide Whether the rescued side was long
     * @param outputToken Token address received
     * @param outputAmount Amount of tokens received
     * @param rescued Whether rescue was successful
     */
    event PositionRescued(
        address indexed user,
        uint256 indexed positionId,
        bool isLongSide,
        address outputToken,
        uint256 outputAmount,
        bool rescued
    );

    event MarketDeleted(bool isLong, uint256 positionId);
    event MarketDeletionFailed(bool isLong, uint256 positionId);

    /**
     * @notice Callback function called by GMX OrderHandler after order execution
     * @dev Processes the executed order, updates position state, and transfers funds to the user
     * @dev Marks proxy as available if both sides of market neutral position are closed
     * @param key The order key from GMX
     * @param orderData Order data from GMX event logs
     * @param eventData Event data from GMX execution
     */
    function afterOrderExecution(
        bytes32 key,
        EventUtils.EventLogData memory orderData,
        EventUtils.EventLogData memory eventData
    ) external override onlyOrderHandler nonReentrant { // discutir si puedo quitar el cntrolador...
        
        (, address orderMarket) = orderData.addressItems.getWithoutRevert("market");
        (, address outputToken) = eventData.addressItems.getWithoutRevert("outputToken");
        (, uint256 outputAmount) = eventData.uintItems.getWithoutRevert("outputAmount");
        uint256 collateralTokenPrice = outputToken == usdc ? 1
            : GMXPrices(addressProvider.getAddress("GMXPrices")).getPrice(gmxMarkets.getMarket("ETHUSDC"));
        uint256 executionPrice;
        bool isLongSideCalculated = false;

        PairTradingStorage pairTradingStorage = PairTradingStorage(addressProvider.getAddress("PairTradingStorage"));
        PairTradingLib.PendingOrder memory pendingOrder = pairTradingStorage.getPendingOrder(key);
        uint256 proxyId = PairTradingProxy(pendingOrder.proxy).getId();

        try GMXPrices(addressProvider.getAddress("GMXPrices")).getPrice(orderMarket) returns (uint256 price) {
            executionPrice = price;
        } catch {
            executionPrice = 1;
        }

        PairTradingLib.RawExecutionData memory executionData = PairTradingLib.RawExecutionData({
            positionId: pendingOrder.positionId,  
            receiver: pendingOrder.receiver,       
            outputToken: outputToken,            
            outputAmount: outputAmount, 
            pnl: 0,                      
            executionPrice: executionPrice,        
            collateralTokenPrice: collateralTokenPrice, 
            isLongSide: false, 
            processed: false,
            timestamp: block.timestamp
        });
        
        pairTradingStorage.storeRawExecutionData(key, executionData); // seguro que hay datos que no necesitamos
        
        try this.calculateIsLongSide(pendingOrder.receiver, pendingOrder.positionId, orderMarket) returns (bool isLong) {
            PairTradingLib.RawExecutionData memory data = pairTradingStorage.getRawExecutionData(key);
            data.isLongSide = isLong;
            pairTradingStorage.storeRawExecutionData(key, data); // we can store just the isLongSide... no need to store the whole data, create a new function for that.
            isLongSideCalculated = true;
            try ProxyManager(addressProvider.getAddress("ProxyManager")).deleteMarket(isLong, pendingOrder.positionId, proxyId, pendingOrder.receiver) {
                emit MarketDeleted(isLong, pendingOrder.positionId);
            } catch {
                emit MarketDeletionFailed(isLong, pendingOrder.positionId);
            }
        } catch {
            emit IsLongSideCalculationFailed(key, pendingOrder.positionId);
        }
                
        try this.processAndTransfer(key, address(pairTradingStorage)) {
            pairTradingStorage.updateExecutionProcessed(key, true);
            pairTradingStorage.removeUserPendingOrderKey(pendingOrder.receiver, key);
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(proxyId);

            emit PositionSideClosedSuccess(
                pendingOrder.receiver,
                pendingOrder.positionId,
                isLongSideCalculated,
                outputToken,
                outputAmount
            );
        } catch Error(string memory reason) {
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, reason);
        } catch {
            emit ExecutionProcessingFailed(key, pendingOrder.positionId, pendingOrder.receiver, "Unknown error");
        }
    }

    /**
     * @notice Determines if the closed order corresponds to the long side of the position
     * @dev Separated function to allow try-catch handling
     * @dev Compares the order market with the long market stored in position data
     * @param receiver Address of the position owner
     * @param positionId The position ID
     * @param orderMarket Market address from the executed order
     * @return true if the order is for the long side, false if short
     */
    function calculateIsLongSide(
        address receiver,
        uint256 positionId,
        address orderMarket
    ) external view returns (bool) {
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(receiver, positionId);
        address marketLong = abi.decode(position.positionData[2], (address));
        return (orderMarket == marketLong);
    }

    /**
     * @notice Processes execution data and transfers funds to the user
     * @dev Updates position state, calculates PNL, and transfers output tokens
     * @dev External function to allow try-catch handling, only callable internally
     * @param key The order key from GMX
     * @param _pairTradingStorage Address of PairTradingStorage contract
     */
    function processAndTransfer(bytes32 key, address _pairTradingStorage) external {
        if(msg.sender != address(this)) revert InvalidSender();
        PairTradingLib.RawExecutionData memory data = PairTradingStorage(_pairTradingStorage).getRawExecutionData(key);
        if(data.processed) revert AlreadyProcessed();
        
        ProtocolStorage _protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        ProtocolLib.Position memory position = _protocolStorage.getUserPositionById(data.receiver, data.positionId);

        uint256 tokenDecimals = data.outputToken == usdc ? 6 : 18;
        uint256 outputUsdValue = (data.outputAmount * data.collateralTokenPrice) / (10 ** tokenDecimals);
        
        if (data.isLongSide) {
            position.positionData[12] = abi.encode(data.executionPrice);
        } else {
            position.positionData[13] = abi.encode(data.executionPrice);
        }
        
        uint256 currentFinalUsdValue = abi.decode(position.positionData[11], (uint256));
        uint256 totalFinalUsdValue = currentFinalUsdValue + outputUsdValue;
        position.positionData[11] = abi.encode(totalFinalUsdValue);

        int256 currentPnl = abi.decode(position.positionData[14], (int256));
        uint256 initialUsdValueHalf = abi.decode(position.positionData[8], (uint256)) / 2;
        uint256 totalFinalUsdValueScaled = totalFinalUsdValue * 10**tokenDecimals;
        int256 totalPnl = currentPnl - (int256(initialUsdValueHalf) - int256(totalFinalUsdValueScaled));
        position.positionData[14] = abi.encode(totalPnl);
        position.pnl = totalPnl;
        
        uint256 finalPriceTokenLong = abi.decode(position.positionData[12], (uint256));
        uint256 finalPriceTokenShort = abi.decode(position.positionData[13], (uint256));
        bool bothSidesClosed = (finalPriceTokenLong != 0 && finalPriceTokenShort != 0);
        
        if (bothSidesClosed) {
            position.positionData[10] = abi.encode(block.timestamp);
            position.isActive = false;
            _protocolStorage.decreaseGlobalPositionActivePositions(data.receiver);
        }
        
        _protocolStorage.updateUserFullPosition(data.receiver, data.positionId, position); // aqui probablemente se pueda optimizar
        
        PairTradingStorage(_pairTradingStorage).updatePendingOrder(
            key, 
            PairTradingLib.PendingOrder(data.receiver, address(0), data.positionId, false) // aqui probablemente se pueda optimizar
        );
        
        if (data.outputAmount > 0) {
            if (data.outputToken == weth) {
                IWETH(weth).withdraw(data.outputAmount);
                (bool success, ) = data.receiver.call{value: data.outputAmount}("");
                require(success, "ETH transfer failed");
            } else {
                // aqui if(performance fee isActivated) transfer performance fee to fee manager contract
                // o llamada view a fee manager contract para obtener instrucciones de envios.
                IERC20(data.outputToken).safeTransfer(data.receiver, data.outputAmount);
            }
        }
    }

    /**
     * @notice Callback for order cancellation (not implemented)
     * @dev Placeholder for future implementation
     * @param key The order key
     * @param order Order data
     * @param eventData Event data
     */
    function afterOrderCancellation(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}
    
    /**
     * @notice Callback for frozen orders (not implemented)
     * @dev Placeholder for future implementation
     * @param key The order key
     * @param order Order data
     * @param eventData Event data
     */
    function afterOrderFrozen(bytes32 key, EventUtils.EventLogData memory order, EventUtils.EventLogData memory eventData) external {}

    /**
     * @notice Refunds execution fee to the user when order is cancelled or fails
     * @dev Called by GMX when execution fee needs to be refunded
     * @param key The order key
     * Event data (unused)
     */
    function refundExecutionFee(bytes32 key, EventUtils.EventLogData memory /* eventData */) external payable {
        PairTradingLib.PendingOrder memory pendingOrder = PairTradingStorage(addressProvider.getAddress("PairTradingStorage")).getPendingOrder(key);
        if (msg.value > 0 && pendingOrder.receiver != address(0)) {
            (bool success, ) = pendingOrder.receiver.call{value: msg.value}("");
            require(success, "Refund execution fee transfer failed");
        }
    }   

    /**
     * @notice Rescue function for when callback execution fails
     * @dev Allows users to manually process their position closure when automatic callback fails
     * @dev Only requires the orderKey - execution data is already stored on-chain
     * @param key The order key that failed (from ExecutionProcessingFailed event)
     */
    function rescuePosition(bytes32 key) external nonReentrant {
        address pairTradingStorage = addressProvider.getAddress("PairTradingStorage");
        PairTradingLib.RawExecutionData memory data = PairTradingStorage(pairTradingStorage).getRawExecutionData(key);
        PairTradingLib.PendingOrder memory pendingOrder = PairTradingStorage(pairTradingStorage).getPendingOrder(key);
        
        require(data.positionId != 0, "No data for this key");
        require(data.receiver == msg.sender, "Not your position");
        require(!data.processed, "Already processed");
        
        try this.processAndTransfer(key, pairTradingStorage) {
            PairTradingStorage(pairTradingStorage).updateExecutionProcessed(key, true);
            PairTradingStorage(pairTradingStorage).removeUserPendingOrderKey(msg.sender, key);
            uint256 proxyId = PairTradingProxy(pendingOrder.proxy).getId();
            ProxyManager(addressProvider.getAddress("ProxyManager")).setAvailable(proxyId);
            emit PositionRescued(
                msg.sender,
                data.positionId,
                data.isLongSide,
                data.outputToken,
                data.outputAmount,
                true
            );
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Rescue failed: ", reason)));
        }
    }
    
    /**
     * @notice Emergency withdrawal of tokens (for extreme edge cases only)
     * @dev Can only be called by authorized protocol admins
     * @dev Used when rescuePosition fails and funds need to be returned manually
     * @param token Token address to withdraw (WETH, USDC, etc). Use address(0) for ETH
     * @param to Destination address (usually the affected user)
     * @param amount Amount to withdraw
     * @param reason Reason for emergency withdrawal (for audit purposes)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount,
        string calldata reason
    ) external nonReentrant {
        require(Roles(addressProvider.getAddress("Roles")).checkAdmin(msg.sender), "Not authorized");
        require(to != address(0), "Invalid destination");
        require(amount > 0, "Amount must be > 0");
        require(bytes(reason).length > 0, "Reason required");
        
        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        
        emit EmergencyWithdraw(msg.sender, token, to, amount, reason, block.timestamp);
    }
    
    /**
     * @notice Emergency withdrawal of ETH (wrapped as WETH)
     * @dev Wrapper for emergencyWithdraw specific to WETH/ETH
     * @param to Destination address
     * @param amount Amount in wei
     * @param unwrap If true, unwrap WETH to ETH before sending
     * @param reason Reason for withdrawal
     */
    function emergencyWithdrawETH(
        address to,
        uint256 amount,
        bool unwrap,
        string calldata reason
    ) external nonReentrant {
        require(Roles(addressProvider.getAddress("Roles")).checkAdmin(msg.sender), "Not authorized");
        require(to != address(0), "Invalid destination");
        require(amount > 0, "Amount must be > 0");
                
        if (unwrap) {
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
            
            emit EmergencyWithdraw(msg.sender, address(0), to, amount, reason, block.timestamp);
        } else {
            IERC20(weth).safeTransfer(to, amount);
            
            emit EmergencyWithdraw(msg.sender, weth, to, amount, reason, block.timestamp);
        }
    }

    error InvalidSender();
    error AlreadyProcessed();

}