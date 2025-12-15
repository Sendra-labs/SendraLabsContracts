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

contract DeployCallback is Script {

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
    
    function run() public {

        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        console.log("Deploying ClosePositionCallbacks...");

        // Usar AddressProvider y Roles existentes
        // Si necesitas usar direcciones diferentes, puedes usar variables de entorno:
        // addressProvider = AddressProvider(vm.envAddress("ADDRESS_PROVIDER"));
        addressProvider = AddressProvider(0x81806092f74bEd8B100c29517Fbb5765fBe592f1);
        roles = Roles(0xa160A99ec745FC1E3Aa6b144971225596a26BfB4);
        
        console.log("Using existing AddressProvider:", address(addressProvider));
        console.log("Using existing Roles:", address(roles));
        
        
        // Desplegar ClosePositionCallbacks
        // Nota: EventUtils (librería usada por ClosePositionCallbacks) se despliega automáticamente
        // por Foundry cuando compila el contrato. No requiere deploy manual.
        console.log("--------------------------------");
        console.log("Deploying ClosePositionCallbacks...");
        closePositionCallbacks = new ClosePositionCallbacks(address(addressProvider));
        console.log("ClosePositionCallbacks deployed at:", address(closePositionCallbacks));
        
        // Registrar en AddressProvider
        console.log("Registering ClosePositionCallbacks in AddressProvider...");
        scriptSetAddresses(address(closePositionCallbacks), "ClosePositionCallbacks");
        
        // Registrar en Roles (allowContract)
        console.log("Registering ClosePositionCallbacks in Roles...");
        scriptAllowContract(address(closePositionCallbacks), "ClosePositionCallbacks");
        
        console.log("--------------------------------");
        console.log("ClosePositionCallbacks successfully deployed and registered:");
        console.log("Address:", address(closePositionCallbacks));
        console.log("Registered in AddressProvider");
        console.log("Registered in Roles:");
        console.log("--------------------------------");

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
