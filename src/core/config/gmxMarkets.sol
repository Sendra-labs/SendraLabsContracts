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

    struct Market {
        address marketAddress;
        bool isUsdcAvailable;
        address collateralToken;
    }

    
    /// @notice Mapping from market symbol hash to market address
    mapping(bytes32 => Market) public markets;
    
    /// @notice Mapping to check if symbol exists
    mapping(bytes32 => bool) public marketExists;
    
    mapping(address => bytes32) public marketsByAddress;

    /**
     * @notice Initialize all markets with current addresses
     * @dev Called in constructor to set initial values
     */
    function _initializeMarkets() internal {
        _addMarket("BTCUSDC", 0x47c031236e19d024b42f8AE6780E44A573170703, true, address(0)); // YES
        _addMarket("ETHUSDC", 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336, true, address(0)); // YES
        _addMarket("LINKUSDC", 0x7f1fa204bb700853D36994DA19F830b6Ad18455C, true, address(0)); // YES
        _addMarket("SOLUSDC", 0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9, true, address(0)); // YES
        _addMarket("DOTUSDC", 0x7B2D09fca2395713dcc2F67323e4876F27b9ecB2, true, address(0)); // YES
        _addMarket("AVAXUSDC", 0x7BbBf946883a5701350007320F525c5379B8178A, true, address(0)); // YES
        _addMarket("BNBUSDC", 0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B, true, address(0)); // YES
        _addMarket("DOGEUSDC", 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4, true, address(0)); // YES
        _addMarket("PEPEUSDC", 0x2b477989A149B17073D9C9C82eC9cB03591e20c6, true, address(0)); // YES
        _addMarket("WIFUSDC", 0x0418643F94Ef14917f1345cE5C460C37dE463ef7, true, address(0)); // YES
        _addMarket("PENDLEUSDC", 0x784292E87715d93afD7cb8C941BacaFAAA9A5102, true, address(0)); // YES
        _addMarket("ARBUSDC", 0xC25cEf6061Cf5dE5eb761b50E4743c1F5D7E5407, true, address(0)); // YES
        _addMarket("OPUSDC", 0x4fDd333FF9cA409df583f306B6F5a7fFdE790739, true, address(0)); // YES
        _addMarket("APEUSDC", 0xdAB21c4d1F569486334C93685Da2b3F9b0A078e8, true, address(0)); // YES
        /*
        _addMarket("XLMUSDC", 0xe902D1526c834D5001575b2d0Ef901dfD0aa097A, true, address(0)); // NO
        _addMarket("SUIUSDC", 0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797, true, address(0)); // NO
        _addMarket("APTUSDC", 0x66A69c8eb98A7efE22A22611d1967dfec786a708, true, address(0)); // NO
        _addMarket("XRPUSDC", 0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c, true, address(0)); // NO
        _addMarket("LTCUSDC", 0xD9535bB5f58A1a75032416F2dFe7880C30575a41, true, address(0)); // NO
        */
        _addMarket("GMXUSDC", 0x55391D178Ce46e7AC8eaAEa50A72D1A5a8A622Da, true, address(0)); // YES
        _addMarket("AAVEUSDC", 0x1CbBa6346F110c8A5ea739ef2d1eb182990e4EB2, true, address(0)); //  YES
        _addMarket("UNIUSDC", 0xc7Abb2C5f3BF3CEB389dF0Eecd6120D451170B50, true, address(0)); //  YES
        _addMarket("ADAUSDC", 0xcaCb964144f9056A8f99447a303E60b4873Ca9B4, true, address(0)); //  YES
        _addMarket("TAOUSDC", 0xe55e1A29985488A2c8846a91E925c2B7C6564db1, true, address(0)); //  YES
        _addMarket("ATOMUSDC", 0x248C35760068cE009a13076D573ed3497A47bCD4, true, address(0)); //  YES
        _addMarket("LDOUSDC", 0xE61e608Ba010fF48A7dcE8eDd8B906744263d33E, true, address(0)); //  YES
        _addMarket("TRXUSDC", 0x3680D7bFE9260D3c5DE81AEB2194c119a59A99D1, true, address(0)); // NO
        _addMarket("ONDOUSDC", 0xa8A455Ed94b315460CfF7d96966d91330f6A3bA0, true, address(0)); // NO
        _addMarket("NEARUSDC", 0x63Dc80EE90F26363B3FCD609007CC9e14c8991BE, true, address(0)); // YES
        _addMarket("TIAUSDC", 0xBeB1f4EBC9af627Ca1E5a75981CE1AE97eFeDA22, true, address(0)); // YES
        _addMarket("INJUSDC", 0x16466a03449CB9218EB6A980Aa4a44aaCEd27C25, true, address(0)); // NO
        _addMarket("CAKEUSDC", 0xdE967676db7b1ccdBA2bD94B01B5b19DE4b563e4, true, address(0)); // YES
        _addMarket("POLUSDC", 0xD0a1AFDDE31Eb51e8b53bdCE989EB8C2404828a4, true, address(0)); // NO
        _addMarket("SHIBUSDC", 0xB62369752D8Ad08392572db6d0cc872127888beD, true, address(0)); // NO
        _addMarket("FILUSDC", 0x262B5203f0fe00D9fe86ffecE01D0f54fC116180, true, address(0)); // NO
        _addMarket("FETUSDC", 0x970e578fF01589Bb470CE38a2f1753152A009366, true, address(0)); // NO 
        _addMarket("TONUSDC", 0x15c6eBD4175ffF9EE3c2615c556fCf62D2d9499c, true, address(0)); // NO
        _addMarket("JUPUSDC", 0x7DE8E1A1fbA845A330A6bD91118AfDA09610fB02, true, address(0)); // NO
        _addMarket("DYDXUSDC", 0x467C4A46287F6C4918dDF780D4fd7b46419c2291, true, address(0)); // NO
        _addMarket("BCHUSDC", 0x62feB8Ec060A7dE5b32BbbF4AC70050f8a043C17, true, address(0)); // NO
        _addMarket("STXUSDC", 0xD9377d9B9a2327C7778867203deeA73AB8a68b6B, true, address(0)); // NO
        _addMarket("ZROUSDC", 0x9e79146b3A022Af44E0708c6794F03Ef798381A5, true, address(0)); // YES
        _addMarket("TRUMPUSDC", 0xFec8f404FBCa3b11aFD3b3f0c57507C2a06dE636, true, address(0)); // YES 
        _addMarket("EIGENSDC", 0xD4b737892baB8446Ea1e8Bb901db092fb1EC1791, true, address(0)); // NO
        _addMarket("ALGOUSDC", 0x3B7f4e4Cf2fa43df013d2B32673e6A01d29ab2Ac, true, address(0)); // NO
        _addMarket("HBARUSDC", 0x9f0849FB830679829d1FB759b11236D375D15C78, true, address(0)); // NO
        _addMarket("LINEAUSDC", 0x6d9430A116ed4d4FC6FE1996A5493662d555b07E, true, address(0)); // NO
        _addMarket("ASTERUSDC", 0x0164B6c847c65e07C9F6226149ADBFA7C1dE40Cf, true, address(0)); // NO
    }
    
    /**
     * @notice Internal function to add a market
     * @param symbol Market symbol (e.g., "BTCUSDC")
     * @param marketAddress Address of the GMX market
     */
    function _addMarket(string memory symbol, address marketAddress, bool isUsdcAvailable, address collateralToken) internal {
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        marketsByAddress[marketAddress] = symbolHash;
        markets[symbolHash] = Market({
            marketAddress: marketAddress,
            isUsdcAvailable: isUsdcAvailable,
            collateralToken: collateralToken
        });
        
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
        Market memory oldMarket = markets[symbolHash];
        
        Market memory newMarket = Market({
            marketAddress: newAddress,
            isUsdcAvailable: oldMarket.isUsdcAvailable,
            collateralToken: oldMarket.collateralToken
        });
        
        markets[symbolHash] = newMarket;
        
        emit MarketUpdated(symbol, oldMarket.marketAddress, newMarket.marketAddress);
    }
    
    /**
     * @notice Add a new market (admin only)
     * @param symbol Market symbol (e.g., "NEWUSDC")
     * @param marketAddress Address of the new market
     */
    function addMarket(string calldata symbol, address marketAddress, bool isUsdcAvailable, address collateralToken) 
        external 
        onlyAdmin 
    {
        require(marketAddress != address(0), "Invalid address");
        
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        require(!marketExists[symbolHash], "Market already exists");
        
        _addMarket(symbol, marketAddress, isUsdcAvailable, collateralToken);
        
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
        Market memory market = markets[symbolHash];
        require(market.marketAddress != address(0), "Market not found");
        return market.marketAddress;
    }

    function getMarketCollateralTokenBySymbol(string calldata symbol) external view returns (address) {
        bytes32 symbolHash = keccak256(abi.encode(symbol));
        Market memory market = markets[symbolHash];
        if (market.isUsdcAvailable) {
            return address(0);
        }
        require(market.marketAddress != address(0), "Market not found");
        return market.collateralToken;
    }

    function getMarketCollateralTokenByAddress(address _marketAddress) external view returns (address) {
        bytes32 symbolHash = marketsByAddress[_marketAddress];
        Market memory market = markets[symbolHash];
        if (market.isUsdcAvailable) {
            return address(0);
        }
        require(market.marketAddress != address(0), "Market not found");
        return market.collateralToken;
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
        return markets[symbolHash].marketAddress != address(0);
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