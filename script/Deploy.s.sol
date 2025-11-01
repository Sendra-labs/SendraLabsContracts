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

contract Deploy is Script {

    AddressProvider public addressProvider;
    Roles public roles;
    MarketNeutral public marketNeutral;
    BundlesRouter public bundlesRouter;
    ProtocolStorage public protocolStorage;
    GMXMarketsRegistry public gmxMarketsRegistry;
    GMXPrices public gmxPrices;
    UpgradeableLib public upgradeableLib;

    address public constant ADMIN1 = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336; // CHANGE THIS
    //address public constant ADMIN2 = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336; // CHANGE THIS
    //address public constant ADMIN3 = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336; // CHANGE THIS

    struct Contracts {
        string name;
        address contractAddress;
        bool isAllowanceRequired;
    }

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        roles = new Roles(ADMIN1, ADMIN2, ADMIN3);
        addressProvider = new AddressProvider(address(roles));
        marketNeutral = new MarketNeutral(address(addressProvider));
        bundlesRouter = new BundlesRouter(address(addressProvider));
        protocolStorage = new ProtocolStorage(address(roles));
        gmxMarketsRegistry = new GMXMarketsRegistry(address(roles));
        gmxPrices = new GMXPrices(address(addressProvider));
        upgradeableLib = new UpgradeableLib(address(roles));

        console.log("--------------------------------");
        console.log("Roles -------------> ", address(roles));
        console.log("AddressProvider ---> ", address(addressProvider));
        console.log("MarketNeutral -----> ", address(marketNeutral));
        console.log("BundlesRouter -----> ", address(bundlesRouter));
        console.log("ProtocolStorage ---> ", address(protocolStorage));
        console.log("GMXMarketsRegistry -> ", address(gmxMarketsRegistry));
        console.log("GMXPrices --------> ", address(gmxPrices));
        console.log("UpgradeableLib ----> ", address(upgradeableLib));
        console.log("--------------------------------");
        
        Contracts[] memory contracts = new Contracts[](6);
        contracts[0] = Contracts("BundlesRouter", address(bundlesRouter), true);
        contracts[1] = Contracts("MarketNeutral", address(marketNeutral), true);
        contracts[2] = Contracts("ProtocolStorage", address(protocolStorage), false);
        contracts[3] = Contracts("AddressProvider", address(addressProvider), false);
        contracts[4] = Contracts("GMXMarketsRegistry", address(gmxMarketsRegistry), false);
        contracts[5] = Contracts("GMXPrices", address(gmxPrices), false);

        scriptManager(contracts);

        vm.stopBroadcast();
    }

    function scriptManager(Contracts[] memory _contracts) public {
        for(uint i = 0; i < _contracts.length; i++) {
            scriptSetAddresses(_contracts[i].contractAddress, _contracts[i].name);
            if(_contracts[i].isAllowanceRequired) {
                scriptAllowContract(_contracts[i].contractAddress, _contracts[i].name);
            }
        }
    }

    function scriptAllowContract(address _contract, string memory _name) public {
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        roles.allowContract(_contract, _name);
        vm.stopBroadcast();

        vm.startBroadcast(ADMIN2_PRIVATE_KEY);
        roles.allowContract(_contract, _name);
        vm.stopBroadcast();
    }

    function scriptSetAddresses(address _address, string memory _name) public {
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        addressProvider.setAddress(_name, _address);
        vm.stopBroadcast();
    }

}
