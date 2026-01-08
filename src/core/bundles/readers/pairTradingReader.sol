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

import { AddressProvider } from "../../config/AddressProvider.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { PairTradingLib } from "../../../lib/PairTrading/PairTradingLib.sol";
import { IReader } from "../../../interfaces/GMX/IReader.sol";
import { GMXPrices } from "../../../periphery/utilsGMX/GMXPrices.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// GMX Types imports

/**
 * @title PairTradingReader
 * @notice Reader contract for Market Neutral positions
 * @dev Provides functions to read position data from GMX and calculate real-time metrics
 */
contract PairTradingReader {
    
    AddressProvider public immutable addressProvider;
    
    /**
     * @notice Constructor
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }
    
    /**
     * @notice Gets basic position data from GMX DataStore
     * @dev These are historical data stored when the position was opened/modified
     * @param positionKey The position key (calculated with calculatePositionKey)
     * @return position Struct with position data
     */
    function getPositionFromGMX(
        bytes32 positionKey
    ) public view returns (IReader.Position memory position) {
        IReader reader = IReader(addressProvider.getAddress("ReaderGMX"));
        address dataStore = addressProvider.getAddress("GMXDataStore");
        
        return reader.getPosition(dataStore, positionKey);
    }
    
    /**
     * @notice Verifies if a position exists in GMX
     * @param positionKey The position key
     * @return exists true if position exists and has size > 0
     */
    function positionExistsInGMX(
        bytes32 positionKey
    ) public view returns (bool exists) {
        IReader.Position memory position = getPositionFromGMX(positionKey);
        return position.sizeInUsd > 0;
    }
    
    /**
     * @notice Gets position size in USD
     * @param positionKey The position key
     * @return sizeInUsd Position size in USD (30 decimals)
     */
    function getPositionSize(bytes32 positionKey) public view returns (uint256 sizeInUsd) {
        IReader.Position memory position = getPositionFromGMX(positionKey);
        return position.sizeInUsd;
    }
    
    /**
     * @notice Gets position collateral amount
     * @param positionKey The position key
     * @return collateralAmount Collateral amount in token decimals
     */
    function getPositionCollateral(bytes32 positionKey) 
        public view returns (uint256 collateralAmount) 
    {
        IReader.Position memory position = getPositionFromGMX(positionKey);
        return position.collateralAmount;
    }
    
    /**
     * @notice Gets position opening timestamp
     * @param positionKey The position key
     * @return timestamp Opening timestamp
     */
    function getPositionOpenTime(bytes32 positionKey) 
        public view returns (uint256 timestamp) 
    {
        IReader.Position memory position = getPositionFromGMX(positionKey);
        return position.increasedAtTime;
    }
    
    /**
     * @notice Checks if position is long or short
     * @param positionKey The position key
     * @return isLong true if long position, false if short
     */
    function isLongPosition(bytes32 positionKey) public view returns (bool isLong) {
        IReader.Position memory position = getPositionFromGMX(positionKey);
        return position.isLong;
    }
    
    /**
     * @notice Gets Market Neutral position data from ProtocolStorage
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return position ProtocolLib.Position struct
     */
    function getPairTradingPosition(
        address user,
        uint256 positionId
    ) public view returns (ProtocolLib.Position memory position) {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        return protocolStorage.getUserPositionById(user, positionId);
    }
    
    /**
     * @notice Extracts position keys from Market Neutral position data
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return longKey Long position key
     * @return shortKey Short position key
     */
    function getPairTradingPositionKeys(
        address user,
        uint256 positionId
    ) public view returns (bytes32 longKey, bytes32 shortKey) {
        ProtocolLib.Position memory position = getPairTradingPosition(user, positionId);
        
        longKey = abi.decode(position.positionData[15], (bytes32));
        shortKey = abi.decode(position.positionData[16], (bytes32));
        
        return (longKey, shortKey);
    }
    
    /**
     * @notice Extracts market addresses from Market Neutral position data
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return marketLong Long market address
     * @return marketShort Short market address
     */
    function getPairTradingMarkets(
        address user,
        uint256 positionId
    ) public view returns (address marketLong, address marketShort) {
        ProtocolLib.Position memory position = getPairTradingPosition(user, positionId);
        
        marketLong = abi.decode(position.positionData[2], (address));
        marketShort = abi.decode(position.positionData[3], (address));
        
        return (marketLong, marketShort);
    }
    
    /**
     * @notice Gets basic position info for both sides of Market Neutral strategy
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return longPosition Long position data from GMX
     * @return shortPosition Short position data from GMX
     */
    function getPairTradingBasicInfo(
        address user,
        uint256 positionId
    ) public view returns (
        IReader.Position memory longPosition,
        IReader.Position memory shortPosition
    ) {
        (bytes32 longKey, bytes32 shortKey) = getPairTradingPositionKeys(user, positionId);
        
        longPosition = getPositionFromGMX(longKey);
        shortPosition = getPositionFromGMX(shortKey);
        
        return (longPosition, shortPosition);
    }
    
    /**
     * @notice Verifies if both sides of Market Neutral position exist
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return _bothSidesExist true if both long and short positions exist
     */
    function bothSidesExist(
        address user,
        uint256 positionId
    ) public view returns (bool _bothSidesExist) {
        (IReader.Position memory longPosition, IReader.Position memory shortPosition) = 
            getPairTradingBasicInfo(user, positionId);
            
        return (longPosition.sizeInUsd > 0 && shortPosition.sizeInUsd > 0);
    }
    
    /**
     * @notice Gets total size of Market Neutral position
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return totalSize Total size in USD (long + short)
     */
    function getPairTradingTotalSize(
        address user,
        uint256 positionId
    ) public view returns (uint256 totalSize) {
        (IReader.Position memory longPosition, IReader.Position memory shortPosition) = 
            getPairTradingBasicInfo(user, positionId);
            
        return longPosition.sizeInUsd + shortPosition.sizeInUsd;
    }
    
    /**
     * @notice Gets total collateral of Market Neutral position
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return totalCollateral Total collateral amount
     * @dev Note: This returns raw amounts, not converted to USD
     */
    function getPairTradingTotalCollateral(
        address user,
        uint256 positionId
    ) public view returns (uint256 totalCollateral) {
            (IReader.Position memory longPosition, IReader.Position memory shortPosition) = 
            getPairTradingBasicInfo(user, positionId);
            
        return longPosition.collateralAmount + shortPosition.collateralAmount;
    }
    
    /**
     * @notice Gets complete position information with real-time PNL from GMX
     * @dev This function consumes more gas than getPositionFromGMX but provides real-time data
     * @param positionKey The position key
     * @param market Market address
     * @return positionInfo Complete PositionInfo struct with PNL, fees, etc.
     */
    function getPositionInfoFromGMX(
        bytes32 positionKey,
        address market
    ) public view returns (IReader.PositionInfo memory positionInfo) {
        IReader reader = IReader(addressProvider.getAddress("ReaderGMX"));
        address dataStore = addressProvider.getAddress("GMXDataStore");
        address referralStorage = addressProvider.getAddress("ReferralStorageGMX");
        
        // Get current market prices
        IReader.MarketPrices memory prices = _getCurrentMarketPrices(market);
        
        return reader.getPositionInfo(
            dataStore,
            referralStorage,
            positionKey,
            prices,
            0,              // sizeDeltaUsd = 0 (we want full position)
            address(0),     // uiFeeReceiver (not applicable for queries)
            true            // usePositionSizeAsSizeDeltaUsd = true
        );
    }
    
    /**
     * @notice Helper function to get current market prices
     * @dev Uses GMXPrices to get prices from Chainlink/other oracles
     * @param market Market address
     * @return prices MarketPrices struct with market prices
     */
    function _getCurrentMarketPrices(
        address market
    ) internal view returns (IReader.MarketPrices memory prices) {
        GMXPrices gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));        
        (
            uint256 indexPrice,
            uint256 longPrice,
            uint256 shortPrice
        ) = gmxPrices.getMarketPrices(market);
        
        // Build price struct
        // NOTE: For simplicity, using same price for min/max
        // In production, consider bid/ask spread
        prices = IReader.MarketPrices({
            indexTokenPrice: IReader.Price({
                min: indexPrice,
                max: indexPrice
            }),
            longTokenPrice: IReader.Price({
                min: longPrice,
                max: longPrice
            }),
            shortTokenPrice: IReader.Price({
                min: shortPrice,
                max: shortPrice
            })
        });
        
        return prices;
    }
    
    /**
     * @notice Gets real-time PNL for both sides of Market Neutral position
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return longPnl PNL of long position in USD (30 decimals)
     * @return shortPnl PNL of short position in USD (30 decimals)
     * @return totalPnl Total PNL (longPnl + shortPnl)
     */
    function getPairTradingRealTimePnL(
        address user,
        uint256 positionId
    ) public view returns (
        int256 longPnl,
        int256 shortPnl,
        int256 totalPnl
    ) {
        (bytes32 longKey, bytes32 shortKey) = getPairTradingPositionKeys(user, positionId);
        (address marketLong, address marketShort) = getPairTradingMarkets(user, positionId);
        
        // Get real-time position info for both sides
        IReader.PositionInfo memory longInfo = getPositionInfoFromGMX(longKey, marketLong);
        IReader.PositionInfo memory shortInfo = getPositionInfoFromGMX(shortKey, marketShort);
        
        longPnl = longInfo.basePnlUsd;
        shortPnl = shortInfo.basePnlUsd;
        totalPnl = longPnl + shortPnl;
        
        return (longPnl, shortPnl, totalPnl);
    }
    
    /**
     * @notice Gets complete real-time information for both sides of Market Neutral strategy
     * @param user User address
     * @param positionId Position ID in ProtocolStorage
     * @return longInfo Complete info for long position
     * @return shortInfo Complete info for short position
     * @return totalPnl Total PNL (long + short)
     * @return totalFees Total fees (long + short)
     */
    function getPairTradingFullInfo(
        address user,
        uint256 positionId
    ) public view returns (
        IReader.PositionInfo memory longInfo,
        IReader.PositionInfo memory shortInfo,
        int256 totalPnl,
        uint256 totalFees
    ) {
        (bytes32 longKey, bytes32 shortKey) = getPairTradingPositionKeys(user, positionId);
        (address marketLong, address marketShort) = getPairTradingMarkets(user, positionId);
        
        // Get complete position info for both sides
        longInfo = getPositionInfoFromGMX(longKey, marketLong);
        shortInfo = getPositionInfoFromGMX(shortKey, marketShort);
        
        // Calculate totals
        totalPnl = longInfo.basePnlUsd + shortInfo.basePnlUsd;
        totalFees = longInfo.fees.totalCostAmount + shortInfo.fees.totalCostAmount;
        
        return (longInfo, shortInfo, totalPnl, totalFees);
    }
    
    /**
     * @notice Gets PNL for a single position side
     * @param positionKey The position key
     * @param market Market address
     * @return pnl PNL in USD (30 decimals)
     */
    function getPositionPnL(
        bytes32 positionKey,
        address market
    ) public view returns (int256 pnl) {
        IReader.PositionInfo memory info = getPositionInfoFromGMX(positionKey, market);
        return info.basePnlUsd;
    }
    
    /**
     * @notice Gets total fees for a single position side
     * @param positionKey The position key
     * @param market Market address
     * @return totalFees Total fees in collateral token
     */
    function getPositionFees(
        bytes32 positionKey,
        address market
    ) public view returns (uint256 totalFees) {
        IReader.PositionInfo memory info = getPositionInfoFromGMX(positionKey, market);
        return info.fees.totalCostAmount;
    }
    
    /**
     * @notice Converts token amount to USD
     * @param amount Token amount
     * @param price Token price (30 decimals)
     * @param tokenDecimals Token decimals
     * @return usdValue USD value (30 decimals)
     */
    function _convertToUsd(
        uint256 amount,
        IReader.Price memory price,
        uint256 tokenDecimals
    ) internal pure returns (uint256 usdValue) {
        // amount has tokenDecimals
        // price has 30 decimals
        // We want result in 30 decimals
        
        if (tokenDecimals == 18) {
            // amount * price / 1e18 = USD in 30 decimals
            return (amount * price.min) / 1e18;
        } else if (tokenDecimals == 6) {
            // amount * price / 1e6 = USD in 30 decimals
            return (amount * price.min) / 1e6;
        } else {
            return (amount * price.min) / (10 ** tokenDecimals);
        }
    }
    
    /**
     * @notice Gets token decimals
     * @param token Token address
     * @return decimals Token decimals
     */
    function _getTokenDecimals(address token) internal view returns (uint256) {
        address weth = addressProvider.getAddress("WETH");
        address usdc = addressProvider.getAddress("USDC");
        
        if (token == weth) return 18;
        if (token == usdc) return 6;
        
        // Fallback: call token.decimals()
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            return uint256(decimals);
        } catch {
            return 18; // Default
        }
    }

}