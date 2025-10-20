//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../security/Roles.sol";

/**
 * @title GMX Markets Registry
 * @author @Diego-AVZ
 * @notice Upgradeable registry for GMX market addresses
 * @dev Allows admins to update market addresses if GMX changes them
 * @dev Reference: https://arbiscan.io/tokens/label/gmx
 */
contract GMXMarketsRegistry {
    
    Roles public immutable roles;
    
    /// @notice Mapping from market symbol hash to market address
    mapping(bytes32 => address) public markets;
    
    /// @notice Mapping to check if symbol exists
    mapping(bytes32 => bool) public marketExists;
    
    constructor(address _roles) {
        require(_roles != address(0), "Invalid Roles address");
        roles = Roles(_roles);
        
        // Initialize markets with current GMX V2 addresses
        _initializeMarkets();
    }
    
    modifier onlyAdmin() {
        require(roles.checkAdmin(msg.sender), "Not admin");
        _;
    }
    
    /**
     * @notice Initialize all markets with current addresses
     * @dev Called in constructor to set initial values
     */
    function _initializeMarkets() internal {
        _addMarket("BTCUSDC", 0x47c031236e19d024b42f8AE6780E44A573170703);
        _addMarket("ETHUSDC", 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336);
        _addMarket("LINKUSDC", 0x7f1fa204bb700853D36994DA19F830b6Ad18455C);
        _addMarket("SOLUSDC", 0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9);
        _addMarket("DOTUSDC", 0x7B2D09fca2395713dcc2F67323e4876F27b9ecB2);
        _addMarket("AVAXUSDC", 0x7BbBf946883a5701350007320F525c5379B8178A);
        _addMarket("BNBUSDC", 0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B);
        _addMarket("SUIUSDC", 0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797);
        _addMarket("APTUSDC", 0x66A69c8eb98A7efE22A22611d1967dfec786a708);
        _addMarket("XRPUSDC", 0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c);
        _addMarket("LTCUSDC", 0xD9535bB5f58A1a75032416F2dFe7880C30575a41);
        _addMarket("DOGEUSDC", 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4);
        _addMarket("XLMUSDC", 0xe902D1526c834D5001575b2d0Ef901dfD0aa097A);
        _addMarket("PEPEUSDC", 0x2b477989A149B17073D9C9C82eC9cB03591e20c6);
        _addMarket("WIFUSDC", 0x0418643F94Ef14917f1345cE5C460C37dE463ef7);
        _addMarket("PENDLEUSDC", 0x784292E87715d93afD7cb8C941BacaFAAA9A5102);
        _addMarket("ARBUSDC", 0x672fEA44f4583DdaD620d60C1Ac31021F47558Cb);
        _addMarket("OPUSDC", 0x4fDd333FF9cA409df583f306B6F5a7fFdE790739);
        _addMarket("APEUSDC", 0xdAB21c4d1F569486334C93685Da2b3F9b0A078e8);
    }
    
    /**
     * @notice Internal function to add a market
     * @param symbol Market symbol (e.g., "BTCUSDC")
     * @param marketAddress Address of the GMX market
     */
    function _addMarket(string memory symbol, address marketAddress) internal {
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        markets[symbolHash] = marketAddress;
        
        if (!marketExists[symbolHash]) {
            marketExists[symbolHash] = true;
        }
    }
    
    /**
     * @notice Update a market address (admin only)
     * @param symbol Market symbol (e.g., "BTCUSDC")
     * @param newAddress New address of the market
     */
    function updateMarket(string calldata symbol, address newAddress) 
        external 
        onlyAdmin 
    {
        require(newAddress != address(0), "Invalid address");
        
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        address oldAddress = markets[symbolHash];
        
        markets[symbolHash] = newAddress;
        
        emit MarketUpdated(symbol, oldAddress, newAddress);
    }
    
    /**
     * @notice Add a new market (admin only)
     * @param symbol Market symbol (e.g., "NEWUSDC")
     * @param marketAddress Address of the new market
     */
    function addMarket(string calldata symbol, address marketAddress) 
        external 
        onlyAdmin 
    {
        require(marketAddress != address(0), "Invalid address");
        
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        require(!marketExists[symbolHash], "Market already exists");
        
        _addMarket(symbol, marketAddress);
        
        emit MarketAdded(symbol, marketAddress);
    }
    
    /**
     * @notice Get market address by symbol
     * @param symbol Market symbol (e.g., "BTCUSDC")
     * @return Address of the market
     */
    function getMarket(string calldata symbol) 
        external 
        view 
        returns (address) 
    {
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        address marketAddress = markets[symbolHash];
        require(marketAddress != address(0), "Market not found");
        return marketAddress;
    }
    
    /**
     * @notice Check if a market exists
     * @param symbol Market symbol
     * @return True if market exists
     */
    function hasMarket(string calldata symbol) 
        external 
        view 
        returns (bool) 
    {
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        return markets[symbolHash] != address(0);
    }
    
    event MarketUpdated(string indexed symbol, address oldAddress, address newAddress);
    event MarketAdded(string indexed symbol, address marketAddress);
}

/*
// https://arbiscan.io/tokens/label/gmx?subcatid=0&size=100&start=0&col=3&order=desc

    address constant BTC_USDC_MARKET = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address constant ETH_USDC_MARKET = 0x450bb6774Dd8a756274E0ab4107953259d2ac541;
    address constant LINK_USDC_MARKET = 0x7f1fa204bb700853D36994DA19F830b6Ad18455C;
    address constant SUI_USDC_MARKET = 0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797; // erc20 false
    address constant SOL_USDC_MARKET = 0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9;
    address constant DOT_USDC_MARKET = 0x7B2D09fca2395713dcc2F67323e4876F27b9ecB2;
    address constant AVAX_USDC_MARKET = 0x7BbBf946883a5701350007320F525c5379B8178A;
    address constant XRP_USDC_MARKET = 0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c; // erc20 false
    address constant LTC_USDC_MARKET = 0xD9535bB5f58A1a75032416F2dFe7880C30575a41; // erc20 false
    address constant DOGE_USDC_MARKET = 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4;
    address constant XLM_USDC_MARKET = 0xe902D1526c834D5001575b2d0Ef901dfD0aa097A; // erc20 false
    address constant BNB_USDC_MARKET = 0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B;
    address constant APT_USDC_MARKET = 0x66A69c8eb98A7efE22A22611d1967dfec786a708; // erc20 false
    address constant PEPE_USDC_MARKET = 0x2b477989A149B17073D9C9C82eC9cB03591e20c6;
    address constant PENDLE_USDC_MARKET = 0x784292E87715d93afD7cb8C941BacaFAAA9A5102;
    address constant ARB_USDC_MARKET = 0x672fEA44f4583DdaD620d60C1Ac31021F47558Cb;
    address constant OP_USDC_MARKET = 0x4fDd333FF9cA409df583f306B6F5a7fFdE790739; // erc20 false
    address constant APE_USDC_MARKET = 0xdAB21c4d1F569486334C93685Da2b3F9b0A078e8; // erc20 false
    address constant WIF_USDC_MARKET = 0x0418643F94Ef14917f1345cE5C460C37dE463ef7; // erc20 false
 */