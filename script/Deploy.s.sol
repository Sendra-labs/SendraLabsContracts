// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { Roles } from "../src/security/Roles.sol";
import { MarketNeutral } from "../src/core/bundles/executors/MarketNeutral.sol";
import { ProtocolStorage } from "../src/core/ProtocolStorage.sol";
import { GMXMarketsRegistry } from "../src/core/config/gmxMarkets.sol";
import { GMXPrices } from "../src/periphery/utilsGMX/GMXPrices.sol";
import { UpgradeableLib } from "../src/core/UpgradeableLib.sol";
import { ProxyFactory } from "../src/core/bundles/executors/ProxyFactory.sol";
import { ProxyManager } from "../src/core/bundles/storage/ProxyManager.sol";
import { MarketNeutralStorage } from "../src/core/bundles/storage/MarketNeutralStorage.sol";
import { ClosePositionCallbacks } from "../src/core/bundles/executors/callbacks/ClosePositionCallbacks.sol";
import { MarketNeutralReader } from "../src/core/bundles/readers/marketNeutralReader.sol";
import { MainReader } from "../src/core/MainReader.sol";
import { PositionInitializer } from "../src/core/bundles/executors/PositionInitializer.sol";
import { ProxyAccessControl } from "../src/core/bundles/security/proxyAccessControl.sol";

contract Deploy is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");

    AddressProvider public addressProvider;
    Roles public roles;
    MarketNeutral public marketNeutral;
    ProtocolStorage public protocolStorage;
    GMXMarketsRegistry public gmxMarketsRegistry;
    GMXPrices public gmxPrices;
    UpgradeableLib public upgradeableLib;
    ProxyFactory public proxyFactory;
    ProxyManager public proxyManager;
    MarketNeutralStorage public marketNeutralStorage;
    ClosePositionCallbacks public closePositionCallbacks;
    MarketNeutralReader public marketNeutralReader;
    MainReader public mainReader;
    PositionInitializer public positionInitializer;
    ProxyAccessControl public proxyAccessControl;

    address public constant ADMIN1 = 0x7F4C831de10684f85867899708cB49FfbF4983B9; // CHANGE THIS
    address public constant ADMIN2 = 0xdD8f39262841F9425ed9180D0D989312E41EbEEc; // CHANGE THIS
    address public constant ADMIN3 = 0xD023851C8AC8ceC385988e7E5af84b1A6D1f9079; // CHANGE THIS

    struct Contracts {
        string name;
        address contractAddress;
        bool isAllowanceRequired;
    }

    function setUp() public {}
    // ✅ CORRECCIONES APLICADAS:
    // - Agregado PositionInitializer (usado por MarketNeutral)
    // - Agregado ProxyAccessControl (usado por PositionInitializer, ProxyManager, MarketNeutralStorage)
    // - Agregado RouterGMX (usado por MarketNeutral para USDC orders)
    
    function run() public {

        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        console.log("Deploying contracts...");

        roles = new Roles(ADMIN1, ADMIN2, ADMIN3);
        addressProvider = new AddressProvider(address(roles));
        
        console.log("Registering external dependencies...");
        scriptSetAddresses(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8, "GMXDataStore");
        
        scriptSetAddresses(address(roles), "Roles");

        scriptSetAddresses(0x63492B775e30a9E6b4b4761c12605EB9d071d5e9, "OrderHandlerGMX");
        scriptSetAddresses(0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5, "OrderVaultGMX");
        scriptSetAddresses(0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41, "ExchangeRouterGMX");
        scriptSetAddresses(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8, "GMXDataStore");
        scriptSetAddresses(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, "USDC");
        scriptSetAddresses(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, "WETH");
        scriptSetAddresses(0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d, "ReferralStorageGMX");
        scriptSetAddresses(0xf60becbba223EEA9495Da3f606753867eC10d139, "ReaderGMX");

        protocolStorage = new ProtocolStorage(address(roles));
        gmxMarketsRegistry = new GMXMarketsRegistry(address(roles));
        scriptSetAddresses(address(gmxMarketsRegistry), "GMXMarkets");
        marketNeutral = new MarketNeutral(address(addressProvider));
        marketNeutralStorage = new MarketNeutralStorage(address(addressProvider));
        closePositionCallbacks = new ClosePositionCallbacks(address(addressProvider));
        marketNeutralReader = new MarketNeutralReader(address(addressProvider));
        proxyFactory = new ProxyFactory(address(addressProvider));
        
        gmxPrices = new GMXPrices(address(addressProvider));
        
        proxyManager = new ProxyManager(address(addressProvider));
        proxyAccessControl = new ProxyAccessControl(address(roles));
        positionInitializer = new PositionInitializer(address(addressProvider));
        
        scriptSetAddresses(address(protocolStorage), "ProtocolStorage");
    
        scriptSetAddresses(address(gmxPrices), "GMXPrices");
        scriptSetAddresses(address(marketNeutralReader), "MarketNeutralReader");
        scriptSetAddresses(address(proxyAccessControl), "ProxyAccessControl");
        scriptSetAddresses(address(positionInitializer), "PositionInitializer");
        
        mainReader = new MainReader(address(addressProvider));

        console.log("--------------------------------");
        console.log("Roles -------------> ", address(roles));
        console.log("AddressProvider ---> ", address(addressProvider));
        console.log("MarketNeutral -----> ", address(marketNeutral));
        console.log("ProtocolStorage ---> ", address(protocolStorage));
        console.log("GMXMarketsRegistry -> ", address(gmxMarketsRegistry));
        console.log("GMXPrices --------> ", address(gmxPrices));
        console.log("ProxyFactory -----> ", address(proxyFactory));
        console.log("ProxyManager -----> ", address(proxyManager));
        console.log("MarketNeutralStorage -> ", address(marketNeutralStorage));
        console.log("ClosePositionCallbacks -> ", address(closePositionCallbacks));
        console.log("MarketNeutralReader -> ", address(marketNeutralReader));
        console.log("MainReader --------> ", address(mainReader));
        console.log("PositionInitializer -> ", address(positionInitializer));
        console.log("ProxyAccessControl -> ", address(proxyAccessControl));
        console.log("--------------------------------");
        
        Contracts[] memory contracts = new Contracts[](14);
        contracts[0] = Contracts("Roles", address(roles), false);
        contracts[1] = Contracts("MarketNeutral", address(marketNeutral), true);
        contracts[2] = Contracts("ProtocolStorage", address(protocolStorage), false);
        contracts[3] = Contracts("AddressProvider", address(addressProvider), false);
        contracts[4] = Contracts("GMXMarkets", address(gmxMarketsRegistry), false);
        contracts[5] = Contracts("GMXPrices", address(gmxPrices), false);
        contracts[6] = Contracts("ProxyFactory", address(proxyFactory), false);
        contracts[7] = Contracts("ProxyManager", address(proxyManager), true);
        contracts[8] = Contracts("MarketNeutralStorage", address(marketNeutralStorage), false);
        contracts[9] = Contracts("ClosePositionCallbacks", address(closePositionCallbacks), true);
        contracts[10] = Contracts("MarketNeutralReader", address(marketNeutralReader), false);
        contracts[11] = Contracts("MainReader", address(mainReader), false);
        contracts[12] = Contracts("PositionInitializer", address(positionInitializer), true);
        contracts[13] = Contracts("ProxyAccessControl", address(proxyAccessControl), false);
            
        scriptManager(contracts);

        vm.stopBroadcast();
    }

    function scriptManager(Contracts[] memory _contracts) public {
        for(uint i = 0; i < _contracts.length; i++) {
            console.log("Managing contract...", _contracts[i].name);
            scriptSetAddresses(_contracts[i].contractAddress, _contracts[i].name);
            if(_contracts[i].isAllowanceRequired) {
                scriptAllowContract(_contracts[i].contractAddress, _contracts[i].name);
            }
        }
    }

    function scriptAllowContract(address _contract, string memory _name) public {
        roles.allowContract(_contract, _name);
    }
    
    function scriptSetAddresses(address _address, string memory _name) public {
        addressProvider.setAddress(_name, _address);
    }

}
