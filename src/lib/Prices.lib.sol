//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title Prices Library
 * @author @Diego-AVZ
 * @notice Library for fetching prices from Chainlink through GMX DataStore
 * @dev Uses GMX V2 DataStore to get Chainlink price feed addresses, then fetches prices
 */
library PricesLib {
    
    /**
     * @notice Get the price of a token from its Chainlink price feed
     * @param priceFeed Address of the Chainlink price feed
     * @return price The latest price from Chainlink (8 decimals)
     */
    function getPriceFromFeed(address priceFeed) 
        internal 
        view 
        returns (uint256 price) 
    {
        if (priceFeed == address(0)) {
            return 0;
        }
        
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        /*
        require(answer > 0, "Invalid price");
        require(updatedAt > 0, "Price not updated");
        require(block.timestamp - updatedAt < 3600, "Price too old"); // 1 hour max
        */
        return uint256(answer);
    }
    
    /**
     * @notice Get price with decimals info
     * @param priceFeed Address of the Chainlink price feed
     * @return price The latest price
     * @return decimals The number of decimals for the price
     */
    function getPriceWithDecimals(address priceFeed) 
        internal 
        view 
        returns (uint256 price, uint8 decimals) 
    {
        if (priceFeed == address(0)) {
            return (0, 0);
        }
        
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        /*
        require(answer > 0, "Invalid price");
        require(updatedAt > 0, "Price not updated");
        require(block.timestamp - updatedAt < 3600, "Price too old");
        */
        decimals = feed.decimals();
        price = uint256(answer);
        
        return (price, decimals);
    }
}

/**
 * @title Chainlink Aggregator V3 Interface
 * @notice Interface for Chainlink price feeds
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    
    function description() external view returns (string memory);
    
    function version() external view returns (uint256);
    
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

