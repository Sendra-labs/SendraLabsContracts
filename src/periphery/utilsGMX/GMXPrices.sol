//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PricesLib } from "../../lib/Prices.lib.sol";
import { AddressProvider } from "../../core/config/AddressProvider.sol";

/**
 * @title GMX Prices
 * @author @Diego-AVZ
 * @notice Contract for getting market prices from GMX DataStore via Chainlink
 * @dev Integrates with GMX V2 DataStore to fetch Chainlink price feed addresses
 */
contract GMXPrices {
    
    AddressProvider public immutable addressProvider;
    /// @notice GMX DataStore contract address
    IDataStore public immutable dataStore;
    
    /// @notice Keys used by GMX MarketStoreUtils
    bytes32 private constant MARKET_TOKEN = keccak256(abi.encode("MARKET_TOKEN"));
    bytes32 private constant INDEX_TOKEN = keccak256(abi.encode("INDEX_TOKEN"));
    bytes32 private constant LONG_TOKEN = keccak256(abi.encode("LONG_TOKEN"));
    bytes32 private constant SHORT_TOKEN = keccak256(abi.encode("SHORT_TOKEN"));
    bytes32 private constant PRICE_FEED = keccak256(abi.encode("PRICE_FEED"));
    bytes32 private constant MARKET_LIST = keccak256(abi.encode("MARKET_LIST"));
    
    /// @notice GMX uses 30 decimals for internal price representation
    uint256 private constant GMX_PRICE_DECIMALS = 30;
    
    /// @notice Default slippage tolerance in basis points (50 = 0.5%)
    uint256 private constant DEFAULT_SLIPPAGE_BPS = 50;
    
    /**
     * @notice Initialize with AddressProvider
     * @param _addressProvider Address of the AddressProvider contract
     */
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        dataStore = IDataStore(addressProvider.getAddress("GMXDataStore"));
    }
    
    /**
     * @notice Get the token addresses from a GMX market
     * @param marketAddress Address of the GMX market
     * @return indexToken Address of the index token (e.g., WETH for ETH/USD market)
     * @return longToken Address of the long collateral token
     * @return shortToken Address of the short collateral token
     */
    function getMarketTokens(address marketAddress) 
        public 
        view 
        returns (
            address indexToken,
            address longToken,
            address shortToken
        ) 
    {
        Market memory market = getMarket(marketAddress);
        
        return (
            market.indexToken,
            market.longToken,
            market.shortToken
        );
    }
    
    /**
     * @notice Get the Chainlink price feed address for a token
     * @param token Address of the token
     * @return priceFeedAddress Address of the Chainlink price feed
     */
    function getChainlinkPriceFeed(address token) 
        public 
        view 
        returns (address priceFeedAddress) 
    {
        bytes32 key = keccak256(abi.encode(PRICE_FEED, token));
        priceFeedAddress = dataStore.getAddress(key);
        return priceFeedAddress;
    }
    
    /**
     * @notice Get all Chainlink price feed addresses for a market
     * @param marketAddress Address of the GMX market
     * @return indexTokenPriceFeed Price feed for index token
     * @return longTokenPriceFeed Price feed for long collateral token
     * @return shortTokenPriceFeed Price feed for short collateral token
     */
    function getMarketPriceFeeds(address marketAddress) 
        public 
        view 
        returns (
            address indexTokenPriceFeed,
            address longTokenPriceFeed,
            address shortTokenPriceFeed
        ) 
    {
        Market memory market = getMarket(marketAddress);
        
        indexTokenPriceFeed = getChainlinkPriceFeed(market.indexToken);
        longTokenPriceFeed = getChainlinkPriceFeed(market.longToken);
        shortTokenPriceFeed = getChainlinkPriceFeed(market.shortToken);
        
        return (indexTokenPriceFeed, longTokenPriceFeed, shortTokenPriceFeed);
    }
    
    /**
     * @notice Get the price of the index token for a market
     * @param marketAddress Address of the GMX market
     * @return price Current price from Chainlink (8 decimals typically)
     */
    function getPrice(address marketAddress) 
        public 
        view 
        returns (uint256 price) 
    {
        Market memory market = getMarket(marketAddress);
        address priceFeed = getChainlinkPriceFeed(market.indexToken);
        //require(priceFeed != address(0), "No price feed for index token");
        
        price = PricesLib.getPriceFromFeed(priceFeed);
        return price;
    }
    
    /**
     * @notice Get all prices for a market from Chainlink
     * @param marketAddress Address of the GMX market
     * @return indexTokenPrice Price of index token
     * @return longTokenPrice Price of long collateral token
     * @return shortTokenPrice Price of short collateral token
     */
    function getMarketPrices(address marketAddress) 
        public 
        view 
        returns (
            uint256 indexTokenPrice,
            uint256 longTokenPrice,
            uint256 shortTokenPrice
        ) 
    {
        (
            address indexFeed,
            address longFeed,
            address shortFeed
        ) = getMarketPriceFeeds(marketAddress);
        /*
        require(indexFeed != address(0), "No price feed for index token");
        require(longFeed != address(0), "No price feed for long token");
        require(shortFeed != address(0), "No price feed for short token");
        */
        indexTokenPrice = PricesLib.getPriceFromFeed(indexFeed);
        longTokenPrice = PricesLib.getPriceFromFeed(longFeed);
        shortTokenPrice = PricesLib.getPriceFromFeed(shortFeed);
        
        return (indexTokenPrice, longTokenPrice, shortTokenPrice);
    }
    
    /**
     * @notice Get market prices with decimals information
     * @param marketAddress Address of the GMX market
     * @return indexPrice Price of index token
     * @return longPrice Price of long token
     * @return shortPrice Price of short token
     * @return indexDecimals Decimals for index token price
     * @return longDecimals Decimals for long token price
     * @return shortDecimals Decimals for short token price
     */
    function getMarketPricesWithDecimals(address marketAddress) 
        public 
        view 
        returns (
            uint256 indexPrice,
            uint256 longPrice,
            uint256 shortPrice,
            uint8 indexDecimals,
            uint8 longDecimals,
            uint8 shortDecimals
        ) 
    {
        (
            address indexFeed,
            address longFeed,
            address shortFeed
        ) = getMarketPriceFeeds(marketAddress);
        
        (indexPrice, indexDecimals) = PricesLib.getPriceWithDecimals(indexFeed);
        (longPrice, longDecimals) = PricesLib.getPriceWithDecimals(longFeed);
        (shortPrice, shortDecimals) = PricesLib.getPriceWithDecimals(shortFeed);
        
        return (indexPrice, longPrice, shortPrice, indexDecimals, longDecimals, shortDecimals);
    }
    
    /**
     * @notice Convert Chainlink price to GMX format (30 decimals)
     * @dev GMX uses 30 decimals for all internal price calculations
     * @param price Price from Chainlink (typically 8 decimals)
     * @param priceDecimals Decimals of the input price
     * @return gmxPrice Price in GMX format (30 decimals)
     */
    function toGMXPrice(uint256 price, uint8 priceDecimals) 
        public 
        pure 
        returns (uint256 gmxPrice) 
    {
        if (priceDecimals == GMX_PRICE_DECIMALS) {
            return price;
        }
        
        if (priceDecimals < GMX_PRICE_DECIMALS) {
            // Scale up
            uint256 scaleFactor = 10 ** (GMX_PRICE_DECIMALS - priceDecimals);
            gmxPrice = price * scaleFactor;
        } else {
            // Scale down
            uint256 scaleFactor = 10 ** (priceDecimals - GMX_PRICE_DECIMALS);
            gmxPrice = price / scaleFactor;
        }
        
        return gmxPrice;
    }
    
    /**
     * @notice Calculate acceptable price for GMX orders with slippage protection
     * @dev Logic based on GMX's BaseOrderUtils.sol:
     *      - INCREASE LONG: acceptablePrice is MAX price you'll pay (current + slippage)
     *      - INCREASE SHORT: acceptablePrice is MIN price you'll accept (current - slippage)
     *      - DECREASE LONG: acceptablePrice is MIN price you'll accept (current - slippage)
     *      - DECREASE SHORT: acceptablePrice is MAX price you'll pay (current + slippage)
     * 
     * @param marketAddress Address of the GMX market
     * @param isLong True for long position, false for short
     * @param isIncrease True for opening/increasing, false for closing/decreasing
     * @param slippageBps Slippage tolerance in basis points (e.g., 50 = 0.5%)
     * @return acceptablePrice Price in GMX format (30 decimals)
     * @return currentPrice Current market price in GMX format (30 decimals)
     */
    function getAcceptablePrice(
        address marketAddress,
        bool isLong,
        bool isIncrease,
        uint256 slippageBps
    ) 
        public 
        view 
        returns (uint256 acceptablePrice, uint256 currentPrice) 
    {
        // Get current price from Chainlink
        (uint256 rawPrice, uint8 decimals) = getMarketPriceWithDecimals(marketAddress);
        
        // Convert to GMX format (30 decimals)
        currentPrice = toGMXPrice(rawPrice, decimals);
        
        // Calculate slippage amount
        uint256 slippageAmount = (currentPrice * slippageBps) / 10000;
        
        // Apply slippage based on position type
        if (isIncrease) {
            if (isLong) {
                // Opening LONG: You're BUYING
                // Protect against price going UP
                // acceptablePrice = current + slippage (max you'll pay)
                acceptablePrice = currentPrice + slippageAmount;
            } else {
                // Opening SHORT: You're SELLING
                // Protect against price going DOWN
                // acceptablePrice = current - slippage (min you'll accept)
                acceptablePrice = currentPrice - slippageAmount;
            }
        } else {
            if (isLong) {
                // Closing LONG: You're SELLING
                // Protect against price going DOWN
                // acceptablePrice = current - slippage (min you'll accept)
                acceptablePrice = currentPrice - slippageAmount;
            } else {
                // Closing SHORT: You're BUYING
                // Protect against price going UP
                // acceptablePrice = current + slippage (max you'll pay)
                acceptablePrice = currentPrice + slippageAmount;
            }
        }
        
        return (acceptablePrice, currentPrice);
    }
    
    /**
     * @notice Get acceptable price with default slippage (0.5%)
     * @param marketAddress Address of the GMX market
     * @param isLong True for long position, false for short
     * @param isIncrease True for opening/increasing, false for closing/decreasing
     * @return acceptablePrice Price in GMX format (30 decimals)
     * @return currentPrice Current market price in GMX format (30 decimals)
     */
    function getAcceptablePriceDefault(
        address marketAddress,
        bool isLong,
        bool isIncrease
    ) 
        external 
        view 
        returns (uint256 acceptablePrice, uint256 currentPrice) 
    {
        return getAcceptablePrice(marketAddress, isLong, isIncrease, DEFAULT_SLIPPAGE_BPS);
    }
    
    /**
     * @notice Helper to get market price with decimals
     * @param marketAddress Address of the GMX market
     * @return price Current price of index token
     * @return decimals Decimals of the price
     */
    function getMarketPriceWithDecimals(address marketAddress)
        public
        view
        returns (uint256 price, uint8 decimals)
    {
        Market memory market = getMarket(marketAddress);
        address priceFeed = getChainlinkPriceFeed(market.indexToken);
        //require(priceFeed != address(0), "No price feed");
        
        return PricesLib.getPriceWithDecimals(priceFeed);
    }
    
    /**
     * @notice Internal function to get market struct from DataStore
     * @dev Uses the same key structure as GMX's MarketStoreUtils
     * @param marketAddress Address of the market
     * @return market Market struct with token addresses
     */
    function getMarket(address marketAddress) 
        internal 
        view 
        returns (Market memory market) 
    {
        /*require(
            dataStore.containsAddress(MARKET_LIST, marketAddress),
            "Market does not exist"
        );*/
        
        market.marketToken = dataStore.getAddress(
            keccak256(abi.encode(marketAddress, MARKET_TOKEN))
        );
        
        market.indexToken = dataStore.getAddress(
            keccak256(abi.encode(marketAddress, INDEX_TOKEN))
        );
        
        market.longToken = dataStore.getAddress(
            keccak256(abi.encode(marketAddress, LONG_TOKEN))
        );
        
        market.shortToken = dataStore.getAddress(
            keccak256(abi.encode(marketAddress, SHORT_TOKEN))
        );
        
        //require(market.marketToken != address(0), "Invalid market");
        
        return market;
    }
}

/**
 * @title Market struct
 * @notice Simplified GMX market structure
 */
struct Market {
    address marketToken;
    address indexToken;
    address longToken;
    address shortToken;
}

/**
 * @title IDataStore
 * @notice Interface for GMX V2 DataStore
 */
interface IDataStore {
    function getAddress(bytes32 key) external view returns (address);
    function getUint(bytes32 key) external view returns (uint256);
    function getBool(bytes32 key) external view returns (bool);
    function containsAddress(bytes32 setKey, address value) external view returns (bool);
}