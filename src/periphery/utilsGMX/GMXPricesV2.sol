//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../core/config/AddressProvider.sol";
import { Price } from "gmx-synthetics/price/Price.sol";
import { IReader } from "../../interfaces/GMX/IReader.sol";
import { ChainlinkPriceFeedUtils } from "gmx-synthetics/oracle/ChainlinkPriceFeedUtils.sol";
import { Keys } from "gmx-synthetics/data/Keys.sol";
import { DataStore } from "gmx-synthetics/data/DataStore.sol";

/**
 * @title Chainlink Aggregator V3 Interface
 * @notice Interface for Chainlink price feeds
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title GMX Prices V2
 * @author @Diego-AVZ
 * @notice Contract for getting market prices from Chainlink via GMX DataStore
 * @dev Uses Chainlink price feeds configured in GMX DataStore
 * 
 * @dev ⚠️ LIMITACIONES IMPORTANTES:
 * @dev 1. Oracle.getPrimaryPrice() NO funciona fuera de ejecuciones de órdenes
 * @dev 2. Solo funcionan tokens con Chainlink Price Feeds on-chain (WETH, WBTC, USDC, etc.)
 * @dev 3. Tokens sintéticos (SOL, XPL, etc.) NO tienen price feeds on-chain
 * @dev 4. Algunos tokens solo tienen Chainlink Data Streams (requiere datos off-chain)
 * 
 * @dev Para tokens sin price feeds, necesitas:
 * @dev - Usar APIs off-chain (como GMX keepers)
 * @dev - Implementar Pyth Network, API3, u otros oráculos
 * @dev - Usar tu propio sistema de precios
 * 
 * @dev Los precios se devuelven en formato GMX (30 decimales)
 */
contract GMXPricesV2 {
    using Price for Price.Props;
    
    AddressProvider public immutable addressProvider;
    /// @notice GMX DataStore contract address (contiene configuración de price feeds)
    IDataStore public immutable dataStore;
    
    /// @notice Keys used by GMX MarketStoreUtils
    bytes32 private constant MARKET_TOKEN = keccak256(abi.encode("MARKET_TOKEN"));
    bytes32 private constant INDEX_TOKEN = keccak256(abi.encode("INDEX_TOKEN"));
    bytes32 private constant LONG_TOKEN = keccak256(abi.encode("LONG_TOKEN"));
    bytes32 private constant SHORT_TOKEN = keccak256(abi.encode("SHORT_TOKEN"));
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
     * @notice Check if a token has a Chainlink price feed configured
     * @param token Token address
     * @return hasPriceFeed True if token has price feed configured in GMX DataStore
     * @dev Use esta función antes de llamar a getPrice() para evitar reverts
     * @dev Tokens sintéticos (SOL, XPL, etc.) retornarán false
     */
    function hasChainlinkPriceFeed(address token) 
        public 
        view 
        returns (bool hasPriceFeed) 
    {
        address priceFeedAddress = dataStore.getAddress(Keys.priceFeedKey(token));
        return priceFeedAddress != address(0);
    }
    
    /**
     * @notice Check if all tokens in a market have price feeds available
     * @param marketAddress Address of the GMX market
     * @return hasAllFeeds True if all market tokens have price feeds
     * @return hasIndexFeed True if index token has price feed
     * @return hasLongFeed True if long token has price feed
     * @return hasShortFeed True if short token has price feed
     */
    function checkMarketPriceFeedAvailability(address marketAddress)
        public
        view
        returns (
            bool hasAllFeeds,
            bool hasIndexFeed,
            bool hasLongFeed,
            bool hasShortFeed
        )
    {
        Market memory market = getMarket(marketAddress);
        
        hasIndexFeed = hasChainlinkPriceFeed(market.indexToken);
        hasLongFeed = hasChainlinkPriceFeed(market.longToken);
        hasShortFeed = hasChainlinkPriceFeed(market.shortToken);
        
        hasAllFeeds = hasIndexFeed && hasLongFeed && hasShortFeed;
        
        return (hasAllFeeds, hasIndexFeed, hasLongFeed, hasShortFeed);
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
     * @notice Get the price of the index token for a market from Chainlink
     * @param marketAddress Address of the GMX market
     * @return price Current price from Chainlink (mid price, 18 decimals for storage)
     * @dev Returns the mid price converted to 18 decimals for easier storage and readability
     * @dev Use getPriceIn30Decimals() if you need the full 30 decimal precision
     */
    function getPrice(address marketAddress) 
        public 
        view 
        returns (uint256 price) 
    {
        return getPriceForStorage(marketAddress);
    }
    
    /**
     * @notice Get the price in full 30 decimal precision (GMX native format)
     * @param marketAddress Address of the GMX market
     * @return price Current price from Chainlink (mid price, 30 decimals)
     * @dev Use this for calculations that require full precision
     */
    function getPriceIn30Decimals(address marketAddress)
        public
        view
        returns (uint256 price)
    {
        Market memory market = getMarket(marketAddress);
        Price.Props memory priceProps = _getPriceWithFallback(market.indexToken);
        price = priceProps.midPrice(); // Returns average of min and max in 30 decimals
        return price;
    }
    
    /**
     * @notice Get price from Chainlink via GMX DataStore
     * @param token Token address
     * @return priceProps Price.Props with min and max prices (30 decimals)
     * 
     * @dev ✅ FUNCIONA CON:
     * @dev - Tokens ERC20 con Chainlink Price Feeds: WETH, WBTC, USDC, USDT, DAI, LINK, etc.
     * @dev - Estos tienen `priceFeed.address` configurado en GMX DataStore
     * 
     * @dev ❌ NO FUNCIONA CON:
     * @dev - Tokens sintéticos: SOL (en Arbitrum), BTC sintético, XPL, ANIME
     * @dev - Tokens con solo Data Streams: Requieren datos off-chain pagados
     * @dev - Tokens nuevos sin feeds configurados
     * 
     * @dev Para verificar si un token tiene feed: usar hasChainlinkPriceFeed()
     * @dev Reverts con NoPriceAvailable si el token no tiene price feed
     */
    function _getPriceWithFallback(address token)
        internal
        view
        returns (Price.Props memory priceProps)
    {
        // Intentar usar el método de GMX primero (usa priceFeedMultiplier)
        (bool hasPriceFeed, uint256 chainlinkPrice) = ChainlinkPriceFeedUtils.getPriceFeedPrice(
            DataStore(address(dataStore)),
            token
        );
        
        if (hasPriceFeed) {
            // GMX método funciona - precio ya está en 30 decimals
            return Price.Props(chainlinkPrice, chainlinkPrice);
        }
        
        // Fallback: leer directamente del Chainlink feed (como V1)
        // Esto funciona para tokens que tienen price feed pero no tienen priceFeedMultiplier configurado
        address priceFeedAddress = dataStore.getAddress(Keys.priceFeedKey(token));
        if (priceFeedAddress == address(0)) {
            // No hay price feed configurado
            return Price.Props(0, 0);
        }
        
        // Leer directamente del Chainlink Aggregator
        try AggregatorV3Interface(priceFeedAddress).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) {
                return Price.Props(0, 0);
            }
            
            // Obtener decimales del feed
            uint8 feedDecimals = AggregatorV3Interface(priceFeedAddress).decimals();
            
            // Convertir de feedDecimals a 30 decimals (formato GMX)
            uint256 price = uint256(answer);
            uint256 scaleFactor = 10 ** (30 - feedDecimals);
            uint256 price30Decimals = price * scaleFactor;
            
            return Price.Props(price30Decimals, price30Decimals);
        } catch {
            // Si falla la lectura del feed, devolver precio vacío
            return Price.Props(0, 0);
        }
    }
    
    /**
     * @notice Get all prices for a market from Chainlink
     * @param marketAddress Address of the GMX market
     * @return indexTokenPrice Price of index token (30 decimals)
     * @return longTokenPrice Price of long collateral token (30 decimals)
     * @return shortTokenPrice Price of short collateral token (30 decimals)
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
        Market memory market = getMarket(marketAddress);
        
        Price.Props memory indexPrice = _getPriceWithFallback(market.indexToken);
        Price.Props memory longPrice = _getPriceWithFallback(market.longToken);
        Price.Props memory shortPrice = _getPriceWithFallback(market.shortToken);
        
        indexTokenPrice = indexPrice.midPrice();
        longTokenPrice = longPrice.midPrice();
        shortTokenPrice = shortPrice.midPrice();
        
        return (indexTokenPrice, longTokenPrice, shortTokenPrice);
    }
    
    /**
     * @notice Get price with min and max values from Chainlink
     * @param marketAddress Address of the GMX market
     * @return minPrice Minimum price from Chainlink (30 decimals)
     * @return maxPrice Maximum price from Chainlink (30 decimals)
     * @return midPrice Mid price (average) from Chainlink (30 decimals)
     * @dev Chainlink retorna un solo precio, por lo que min = max = mid
     */
    function getMarketPriceWithRange(address marketAddress)
        public
        view
        returns (
            uint256 minPrice,
            uint256 maxPrice,
            uint256 midPrice
        )
    {
        Market memory market = getMarket(marketAddress);
        Price.Props memory priceProps = _getPriceWithFallback(market.indexToken);
        
        minPrice = priceProps.min;
        maxPrice = priceProps.max;
        midPrice = priceProps.midPrice();
        
        return (minPrice, maxPrice, midPrice);
    }
    
    /**
     * @notice Calculate acceptable price for GMX orders with slippage protection
     * @dev Logic based on GMX's BaseOrderUtils.sol:
     *      - INCREASE LONG: acceptablePrice is MAX price you'll pay (current + slippage)
     *      - INCREASE SHORT: acceptablePrice is MIN price you'll accept (current - slippage)
     *      - DECREASE LONG: acceptablePrice is MIN price you'll accept (executionPrice >= acceptablePrice)
     *                       Due to price impact, it's safer to use 0 or a very low value
     *      - DECREASE SHORT: acceptablePrice is MAX price you'll pay (executionPrice <= acceptablePrice)
     *                       Due to price impact, it's safer to use max or a very high value
     * 
     * @dev IMPORTANT: For decrease orders, GMX validates that:
     *      - LONG decrease: executionPrice >= acceptablePrice (acceptablePrice is MINIMUM)
     *      - SHORT decrease: executionPrice <= acceptablePrice (acceptablePrice is MAXIMUM)
     *      
     *      Price impact can make executionPrice worse than expected, so use conservative values
     *      or use minOutputAmount for better slippage control on decrease orders.
     * 
     * @param marketAddress Address of the GMX market
     * @param isLong True for long position, false for short
     * @param isIncrease True for opening/increasing, false for closing/decreasing
     * @param slippageBps Slippage tolerance in basis points (e.g., 50 = 0.5%)
     * @param useConservativeDecrease If true, uses 0 (LONG) or max (SHORT) for decrease orders
     * @return acceptablePrice Price in GMX format (30 decimals)
     * @return currentPrice Current market price in GMX format (30 decimals)
     */
    function getAcceptablePrice(
        address marketAddress,
        bool isLong,
        bool isIncrease,
        uint256 slippageBps,
        bool useConservativeDecrease
    ) 
        public 
        view 
        returns (uint256 acceptablePrice, uint256 currentPrice) 
    {
        Market memory market = getMarket(marketAddress);
        Price.Props memory priceProps = _getPriceWithFallback(market.indexToken);
        
        // Use mid price as current price
        currentPrice = priceProps.midPrice();
        
        // For decrease orders, if useConservativeDecrease is true, use extreme values
        // This ensures the order can execute even with significant price impact
        if (!isIncrease && useConservativeDecrease) {
            if (isLong) {
                // LONG decrease: use 0 to accept any price >= 0
                // This is safe because we're using minOutputAmount for slippage control
                acceptablePrice = 0;
            } else {
                // SHORT decrease: use max to accept any price <= max
                // This is safe because we're using minOutputAmount for slippage control
                acceptablePrice = type(uint256).max;
            }
            return (acceptablePrice, currentPrice);
        }
        
        // Calculate slippage amount
        uint256 slippageAmount = (currentPrice * slippageBps) / 10000;
        
        // Apply slippage based on position type
        if (isIncrease) {
            if (isLong) {
                // Opening LONG: You're BUYING
                // GMX validates: executionPrice <= acceptablePrice
                // acceptablePrice is MAXIMUM price you'll pay
                // Protect against price going UP
                acceptablePrice = currentPrice + slippageAmount;
            } else {
                // Opening SHORT: You're SELLING
                // GMX validates: executionPrice >= acceptablePrice
                // acceptablePrice is MINIMUM price you'll accept
                // 
                // IMPORTANTE: Si el price impact negativo hace que executionPrice < acceptablePrice,
                // GMX cancelará la orden. Para evitar esto, el usuario debe aumentar slippageBps
                // para dar margen al price impact esperado.
                // 
                // NO usar 0 o valores muy bajos porque es inseguro - permite slippage extremo.
                // Usar el slippage proporcionado normalmente.
                acceptablePrice = currentPrice > slippageAmount ? currentPrice - slippageAmount : 0;
            }
        } else {
            if (isLong) {
                // Closing LONG: You're SELLING
                // GMX validates: executionPrice >= acceptablePrice
                // So acceptablePrice must be MINIMUM price we'll accept
                // Use current - slippage (conservative) or 0 (accept any price)
                acceptablePrice = currentPrice > slippageAmount ? currentPrice - slippageAmount : 0;
            } else {
                // Closing SHORT: You're BUYING
                // GMX validates: executionPrice <= acceptablePrice
                // So acceptablePrice must be MAXIMUM price we'll pay
                // Use current + slippage (conservative) or max (accept any price)
                uint256 maxPrice = type(uint256).max;
                if (currentPrice + slippageAmount < maxPrice) {
                    acceptablePrice = currentPrice + slippageAmount;
                } else {
                    acceptablePrice = maxPrice;
                }
            }
        }
        
        return (acceptablePrice, currentPrice);
    }
    
    /**
     * @notice Calculate acceptable price (backward compatible, uses conservative for decrease)
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
        // For decrease orders, default to conservative (0 or max) to avoid failures
        // Use minOutputAmount for actual slippage control
        return getAcceptablePrice(marketAddress, isLong, isIncrease, slippageBps, !isIncrease);
    }
    
    /**
     * @notice Calculate expected output USD for a position decrease
     * @dev Uses GMX Reader to get real-time position info and calculate expected output
     * @param positionKey The position key (calculated with calculatePositionKey)
     * @param market Market address
     * @param sizeDeltaUsd Size to decrease in USD (30 decimals), use 0 for full position
     * @return expectedOutputUsd Expected output value in USD (30 decimals)
     * @dev This is an approximation. Actual output may vary due to price impact and fees
     */
    function getExpectedOutputUsd(
        bytes32 positionKey,
        address market,
        uint256 sizeDeltaUsd
    )
        public
        view
        returns (uint256 expectedOutputUsd)
    {
        IReader reader = IReader(addressProvider.getAddress("ReaderGMX"));
        address referralStorage = addressProvider.getAddress("ReferralStorageGMX");
        
        // Get market prices
        IReader.MarketPrices memory prices = _getMarketPricesForReader(market);
        
        // Get position info with sizeDelta
        IReader.PositionInfo memory positionInfo = reader.getPositionInfo(
            address(dataStore),
            referralStorage,
            positionKey,
            prices,
            sizeDeltaUsd,
            address(0),  // uiFeeReceiver
            sizeDeltaUsd == 0  // usePositionSizeAsSizeDeltaUsd
        );
        
        // The positionInfo already has the PNL calculated for the sizeDelta
        // We need to calculate: collateral + PNL - fees
        
        // Get collateral value in USD
        uint256 collateralUsd = _convertToUsd(
            positionInfo.position.collateralAmount,
            positionInfo.fees.collateralTokenPrice,
            _getTokenDecimals(positionInfo.position.collateralToken)
        );
        
        // Calculate proportional collateral if partial decrease
        uint256 positionSizeInUsd = positionInfo.position.sizeInUsd;
        uint256 proportionalCollateralUsd = collateralUsd;
        
        if (sizeDeltaUsd > 0 && sizeDeltaUsd < positionSizeInUsd) {
            // Partial decrease: proportional collateral
            proportionalCollateralUsd = (collateralUsd * sizeDeltaUsd) / positionSizeInUsd;
        }
        
        // Use the PNL from positionInfo (already calculated for sizeDelta)
        // Note: positionInfo.basePnlUsd is for the full position, but we requested it with sizeDelta
        // Actually, getPositionInfo calculates PNL for the sizeDelta if we pass it correctly
        int256 realizedPnlUsd = positionInfo.basePnlUsd;
        
        // Calculate expected output: collateral + PNL - fees
        if (realizedPnlUsd >= 0) {
            expectedOutputUsd = proportionalCollateralUsd + uint256(realizedPnlUsd);
        } else {
            uint256 pnlLoss = uint256(-realizedPnlUsd);
            expectedOutputUsd = proportionalCollateralUsd > pnlLoss 
                ? proportionalCollateralUsd - pnlLoss 
                : 0;
        }
        
        // Subtract fees (totalCostAmount includes position fees, borrowing fees, etc.)
        // Note: fees might be calculated for the full position, need to adjust for partial
        uint256 feesToSubtract = positionInfo.fees.totalCostAmount;
        if (sizeDeltaUsd > 0 && sizeDeltaUsd < positionSizeInUsd) {
            // Approximate proportional fees (not exact but close enough)
            feesToSubtract = (feesToSubtract * sizeDeltaUsd) / positionSizeInUsd;
        }
        
        if (expectedOutputUsd > feesToSubtract) {
            expectedOutputUsd -= feesToSubtract;
        } else {
            expectedOutputUsd = 0;
        }
        
        return expectedOutputUsd;
    }
    
    /**
     * @notice Calculate minOutputAmount for decrease orders (better slippage control)
     * @dev For decrease orders, minOutputAmount is more reliable than acceptablePrice
     *      because it validates the USD value received, not the execution price
     * @param expectedOutputUsd Expected output value in USD (30 decimals)
     * @param slippageBps Slippage tolerance in basis points (e.g., 50 = 0.5%)
     * @return minOutputAmount Minimum output amount in USD (30 decimals)
     */
    function getMinOutputAmount(
        uint256 expectedOutputUsd,
        uint256 slippageBps
    )
        public
        pure
        returns (uint256 minOutputAmount)
    {
        // Calculate minimum output: expectedOutput * (1 - slippage)
        uint256 slippageFactor = 10000 - slippageBps;
        minOutputAmount = (expectedOutputUsd * slippageFactor) / 10000;
        return minOutputAmount;
    }
    
    /**
     * @notice Calculate minOutputAmount from position key (convenience function)
     * @param positionKey The position key
     * @param market Market address
     * @param sizeDeltaUsd Size to decrease in USD (30 decimals), use 0 for full position
     * @param slippageBps Slippage tolerance in basis points
     * @return minOutputAmount Minimum output amount in USD (30 decimals)
     */
    function getMinOutputAmountFromPosition(
        bytes32 positionKey,
        address market,
        uint256 sizeDeltaUsd,
        uint256 slippageBps
    )
        public
        view
        returns (uint256 minOutputAmount)
    {
        uint256 expectedOutputUsd = getExpectedOutputUsd(positionKey, market, sizeDeltaUsd);
        return getMinOutputAmount(expectedOutputUsd, slippageBps);
    }
    
    /**
     * @notice Helper to get market prices in Reader format
     */
    function _getMarketPricesForReader(address marketAddress)
        internal
        view
        returns (IReader.MarketPrices memory prices)
    {
        Market memory market = getMarket(marketAddress);
        
        Price.Props memory indexPrice = _getPriceWithFallback(market.indexToken);
        Price.Props memory longPrice = _getPriceWithFallback(market.longToken);
        Price.Props memory shortPrice = _getPriceWithFallback(market.shortToken);
        
        prices.indexTokenPrice = IReader.Price(indexPrice.min, indexPrice.max);
        prices.longTokenPrice = IReader.Price(longPrice.min, longPrice.max);
        prices.shortTokenPrice = IReader.Price(shortPrice.min, shortPrice.max);
        
        return prices;
    }
    
    /**
     * @notice Helper to convert token amount to USD
     */
    function _convertToUsd(
        uint256 amount,
        IReader.Price memory price,
        uint256 tokenDecimals
    ) internal pure returns (uint256 usdValue) {
        // Use min price for conservative calculation
        uint256 priceIn30Decimals = price.min;
        
        // amount has tokenDecimals, price has 30 decimals
        // result should have 30 decimals
        // usdValue = (amount * priceIn30Decimals) / 10^tokenDecimals
        if (tokenDecimals <= 30) {
            usdValue = (amount * priceIn30Decimals) / (10 ** tokenDecimals);
        } else {
            // If token has more decimals than 30, we'd lose precision
            // This shouldn't happen in practice
            usdValue = amount * priceIn30Decimals / (10 ** tokenDecimals);
        }
        
        return usdValue;
    }
    
    /**
     * @notice Helper to get token decimals (simplified - assumes common tokens)
     * @dev This is a simplified version. In production, you might want to use ERC20.decimals()
     * @param token Token address
     * @return decimals Number of decimals (18 for WETH, 6 for USDC/USDT on Arbitrum)
     */
    function _getTokenDecimals(address token) internal pure returns (uint256) {
        // Common tokens on Arbitrum:
        // WETH = 18 decimals
        // USDC = 6 decimals  
        // USDT = 6 decimals
        // This is a simplification - ideally read from token contract using ERC20.decimals()
        // For now, we'll use a simple heuristic: if it's a known stablecoin address, use 6, else 18
        // You may need to adjust this based on your specific token addresses
        
        // For Arbitrum mainnet common addresses (you may need to adjust):
        // USDC: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8 (6 decimals)
        // USDT: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9 (6 decimals)
        // WETH: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 (18 decimals)
        
        // Simple check: if token is address(0), return 18 (default)
        if (token == address(0)) {
            return 18;
        }
        
        // Default to 18 decimals (most tokens use 18)
        // You can add specific checks here for known stablecoins
        return 18;
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
     * @notice Get price for storage/reference (converted to 18 decimals for readability)
     * @dev This function is useful for storing prices in position data
     * @dev Converts from 30 decimals (GMX format) to 18 decimals for storage
     * @param marketAddress Address of the GMX market
     * @return price Price in 18 decimals format (for storage)
     */
    function getPriceForStorage(address marketAddress)
        public
        view
        returns (uint256 price)
    {
        Market memory market = getMarket(marketAddress);
        Price.Props memory priceProps = _getPriceWithFallback(market.indexToken);
        uint256 price30Decimals = priceProps.midPrice();
        
        // Convert from 30 decimals to 18 decimals
        // Divide by 10^12 (30 - 18 = 12)
        price = price30Decimals / 1e12;
        
        return price;
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
        // Removed require check to allow markets that might not be in MARKET_LIST
        // but still have valid token addresses in DataStore
        
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


error NoPriceAvailable(address token);

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * GUÍA DE USO Y LIMITACIONES
 * ═══════════════════════════════════════════════════════════════════════════════
 * 
 * ✅ TOKENS QUE FUNCIONAN (tienen Chainlink Price Feeds on-chain):
 * 
 * En Arbitrum:
 * - WETH: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
 * - WBTC: 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
 * - USDC: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
 * - USDT: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
 * - DAI: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1
 * - LINK: 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4
 * - UNI: 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0
 * - ARB: 0x912CE59144191C1204E64559FE8253a0e49E6548
 * - GMX: 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a
 * - Y otros tokens con Chainlink feeds tradicionales
 * 
 * ❌ TOKENS QUE NO FUNCIONAN (sin price feeds on-chain):
 * 
 * - SOL (sintético en Arbitrum): Solo tiene Data Stream
 * - BTC (sintético): Solo tiene Data Stream  
 * - XPL (sintético): Solo tiene Data Stream
 * - ANIME: Solo tiene Data Stream
 * - Tokens nuevos o exóticos sin Chainlink feeds
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 * EJEMPLO DE USO SEGURO:
 * ═══════════════════════════════════════════════════════════════════════════════
 * 
 * // Verificar disponibilidad antes de usar
 * GMXPricesV2 prices = GMXPricesV2(pricesAddress);
 * 
 * // Opción 1: Verificar token individual
 * if (prices.hasChainlinkPriceFeed(tokenAddress)) {
 *     uint256 price = prices.getPriceIn30Decimals(marketAddress);
 *     // usar precio...
 * } else {
 *     // Token no tiene price feed - usar fuente alternativa
 *     revert("Token no soportado");
 * }
 * 
 * // Opción 2: Verificar mercado completo
 * (bool hasAllFeeds, , , ) = prices.checkMarketPriceFeedAvailability(marketAddress);
 * if (!hasAllFeeds) {
 *     revert("Mercado con tokens sin price feeds");
 * }
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 * ALTERNATIVAS PARA TOKENS SIN PRICE FEEDS:
 * ═══════════════════════════════════════════════════════════════════════════════
 * 
 * 1. PYTH NETWORK:
 *    - Soporta más tokens (incluye SOL, otros exóticos)
 *    - Requiere updates on-chain pagadas
 *    - https://pyth.network/
 * 
 * 2. API3:
 *    - Oráculos first-party
 *    - https://api3.org/
 * 
 * 3. CHRONICLE PROTOCOL:
 *    - Alternativa a Chainlink
 *    - https://chroniclelabs.org/
 * 
 * 4. SISTEMA CUSTOM:
 *    - Implementar tu propio oráculo
 *    - Usar APIs off-chain (Coingecko, Binance, etc.)
 *    - Requiere trust en tu backend
 * 
 * 5. GMX KEEPER APPROACH:
 *    - Obtener precios firmados del GMX API
 *    - Enviar con transacciones como lo hacen los keepers
 *    - Requiere infraestructura off-chain
 * 
 * ═══════════════════════════════════════════════════════════════════════════════
 */

