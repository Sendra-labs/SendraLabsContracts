// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";

import { Roles } from "../src/security/Roles.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { SendraStorage } from "../src/core/SendraStorage.sol";

// GMX
import { GMXMarketsRegistry } from "../src/core/config/gmxMarkets.sol";
import { GMXPrices } from "../src/periphery/utilsGMX/GMXPrices.sol";

// PairTrading bundle
import { PairTrading } from "../src/core/bundles/executors/PairTrading.sol";
import { PairTradingStorage } from "../src/core/bundles/storage/PairTradingStorage.sol";
import { ClosePositionCallbacks } from "../src/core/bundles/executors/callbacks/ClosePositionCallbacks.sol";
import { PairTradingReader } from "../src/core/bundles/readers/pairTradingReader.sol";
import { ProxyFactory } from "../src/core/bundles/executors/ProxyFactory.sol";
import { ProxyManager } from "../src/core/bundles/storage/ProxyManager.sol";
import { ProxyAccessControl } from "../src/core/bundles/security/proxyAccessControl.sol";
import { PositionInitializer } from "../src/core/bundles/executors/PositionInitializer.sol";
import { PositionManager } from "../src/core/bundles/executors/PositionManager.sol";

// Uniswap bundle
import { LiquidityManager } from "../src/core/uniswap/executors/LiquidityManager.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";

// Readers
import { MainReader } from "../src/core/MainReader.sol";

/**
 * DeploySendraLabs
 * Command:
forge script script/DeploySendraLabs.s.sol:DeploySendraLabs --broadcast --rpc-url arbitrum
 *
 * Env:
 *   ADMIN1_PRIVATE_KEY o PRIVATE_KEY
 */
contract DeploySendraLabs is Script {
    // --- Admin keys ---
    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env");
    }

    // --- Admins (Roles) ---
    address public constant ADMIN1 = 0x85FE59CD064c46711616e44Cff7Ae0D99785D87F;
    address public constant ADMIN2 = 0xdD8f39262841F9425ed9180D0D989312E41EbEEc;
    address public constant ADMIN3 = 0xD023851C8AC8ceC385988e7E5af84b1A6D1f9079;

    // --- Tokens (Arbitrum) ---
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // --- GMX (Arbitrum) ---
    address public constant GMX_DATASTORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
    address public constant GMX_ORDER_HANDLER = 0x63492B775e30a9E6b4b4761c12605EB9d071d5e9;
    address public constant GMX_ORDER_VAULT = 0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;
    address public constant GMX_EXCHANGE_ROUTER = 0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41;
    address public constant GMX_ROUTER = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
    address public constant GMX_REFERRAL_STORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
    address public constant GMX_READER = 0x470fbC46bcC0f16532691Df360A07d8Bf5ee0789;

    // --- Uniswap (Arbitrum) ---
    address public constant UNISWAP_UNIVERSAL_ROUTER = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNISWAP_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // --- Deployed instances (for logs) ---
    Roles public roles;
    AddressProvider public addressProvider;
    SendraStorage public sendraStorage;
    GMXMarketsRegistry public gmxMarkets;
    GMXPrices public gmxPrices;

    PairTrading public pairTrading;
    PairTradingStorage public pairTradingStorage;
    ClosePositionCallbacks public closePositionCallbacks;
    PairTradingReader public pairTradingReader;
    ProxyFactory public proxyFactory;
    ProxyManager public proxyManager;
    ProxyAccessControl public proxyAccessControl;
    PositionInitializer public positionInitializer;
    PositionManager public positionManager;

    LiquidityManager public liquidityManager;
    SwapRouter public swapRouter;
    LiquidityOrchestrator public liquidityOrchestrator;

    MainReader public mainReader;

    function run() public {
        uint256 pk = _getPrivateKey();
        vm.startBroadcast(pk);

        // 1) Roles + AddressProvider
        roles = new Roles(ADMIN1, ADMIN2, ADMIN3);
        addressProvider = new AddressProvider(address(roles));

        // 2) Seed external addresses (tokens + GMX + Uniswap)
        _set("Roles", address(roles));

        _set("USDC", USDC);
        _set("WETH", WETH);

        _set("GMXDataStore", GMX_DATASTORE);
        _set("OrderHandlerGMX", GMX_ORDER_HANDLER);
        _set("OrderVaultGMX", GMX_ORDER_VAULT);
        _set("ExchangeRouterGMX", GMX_EXCHANGE_ROUTER);
        _set("RouterGMX", GMX_ROUTER);
        _set("ReferralStorageGMX", GMX_REFERRAL_STORAGE);
        _set("ReaderGMX", GMX_READER);

        _set("UniswapV3Factory", UNISWAP_V3_FACTORY);
        _set("UniswapNFTPositionManager", UNISWAP_NFT_POSITION_MANAGER);

        // 3) Core storage + GMX helpers
        sendraStorage = new SendraStorage(address(roles));
        _set("SendraStorage", address(sendraStorage));

        gmxMarkets = new GMXMarketsRegistry(address(roles));
        _set("GMXMarkets", address(gmxMarkets));

        gmxPrices = new GMXPrices(address(addressProvider));
        _set("GMXPrices", address(gmxPrices));

        // 4) PairTrading bundle
        pairTrading = new PairTrading(address(addressProvider));
        _set("PairTrading", address(pairTrading));

        pairTradingStorage = new PairTradingStorage(address(addressProvider));
        _set("PairTradingStorage", address(pairTradingStorage));

        closePositionCallbacks = new ClosePositionCallbacks(address(addressProvider));
        _set("ClosePositionCallbacks", address(closePositionCallbacks));

        pairTradingReader = new PairTradingReader(address(addressProvider));
        _set("PairTradingReader", address(pairTradingReader));

        proxyFactory = new ProxyFactory(address(addressProvider));
        _set("ProxyFactory", address(proxyFactory));

        proxyManager = new ProxyManager(address(addressProvider));
        _set("ProxyManager", address(proxyManager));

        proxyAccessControl = new ProxyAccessControl(address(roles));
        _set("ProxyAccessControl", address(proxyAccessControl));

        positionInitializer = new PositionInitializer(address(addressProvider));
        _set("PositionInitializer", address(positionInitializer));

        positionManager = new PositionManager(address(addressProvider));
        _set("PositionManager", address(positionManager));

        // 5) Uniswap bundle
        liquidityManager = new LiquidityManager(address(addressProvider));
        _set("LiquidityManager", address(liquidityManager));

        swapRouter = new SwapRouter(UNISWAP_UNIVERSAL_ROUTER);
        _set("SwapRouter", address(swapRouter));
        _set("swapRouter", address(swapRouter)); // IMPORTANT: LiquidityManager expects lowercase key

        liquidityOrchestrator = new LiquidityOrchestrator(address(addressProvider));
        _set("LiquidityOrchestrator", address(liquidityOrchestrator));

        // 6) Main reader
        mainReader = new MainReader(address(addressProvider));
        _set("MainReader", address(mainReader));

        // 7) Whitelist protocol contracts (onlyProtocol / Roles.isProtocolContract)
        //    Contracts that call SendraStorage (onlyProtocol) must be authorized.
        _allow(address(positionInitializer), "PositionInitializer");
        _allow(address(positionManager), "PositionManager");
        _allow(address(closePositionCallbacks), "ClosePositionCallbacks");
        _allow(address(liquidityOrchestrator), "LiquidityOrchestrator");
        _allow(address(proxyManager), "ProxyManager");

        // (Optional) mark as protocol if you want broader access control
        // _allow(address(liquidityManager), "LiquidityManager");

        _printSummary();

        vm.stopBroadcast();
    }

    function _set(string memory key, address value) internal {
        addressProvider.setAddress(key, value);
    }

    function _allow(address c, string memory name) internal {
        roles.allowContract(c, name);
    }

    function _printSummary() internal view {
        console.log("================================");
        console.log("Roles -------------------->", address(roles));
        console.log("AddressProvider ---------->", address(addressProvider));
        console.log("SendraStorage ------------>", address(sendraStorage));
        console.log("GMXMarkets --------------->", address(gmxMarkets));
        console.log("GMXPrices ---------------->", address(gmxPrices));
        console.log("PairTrading -------------->", address(pairTrading));
        console.log("PairTradingStorage ------->", address(pairTradingStorage));
        console.log("ClosePositionCallbacks --->", address(closePositionCallbacks));
        console.log("PairTradingReader -------->", address(pairTradingReader));
        console.log("ProxyFactory ------------->", address(proxyFactory));
        console.log("ProxyManager ------------->", address(proxyManager));
        console.log("ProxyAccessControl ------->", address(proxyAccessControl));
        console.log("PositionInitializer ------>", address(positionInitializer));
        console.log("PositionManager ---------->", address(positionManager));
        console.log("LiquidityManager --------->", address(liquidityManager));
        console.log("SwapRouter --------------->", address(swapRouter));
        console.log("LiquidityOrchestrator ---->", address(liquidityOrchestrator));
        console.log("MainReader --------------->", address(mainReader));
        console.log("================================");
    }
}

