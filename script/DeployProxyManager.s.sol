// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { ProxyManager } from "../src/core/bundles/storage/ProxyManager.sol";

contract DeployProxyManager is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");
    
    // Dirección del AddressProvider ya desplegado (cambiar según tu deployment)
    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;

    function setUp() public {}

    function run() public {
        // Verificar que AddressProvider esté configurado
        require(ADDRESS_PROVIDER != address(0), "AddressProvider address not set");
        
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        
        console.log("========================================");
        console.log("Deploying ProxyManager contract...");
        console.log("========================================");
        
        // Desplegar ProxyManager
        ProxyManager proxyManager = new ProxyManager(ADDRESS_PROVIDER);
        
        console.log("ProxyManager deployed at:", address(proxyManager));
        
        // Registrar en AddressProvider
        AddressProvider addressProvider = AddressProvider(ADDRESS_PROVIDER);
        addressProvider.setAddress("ProxyManager", address(proxyManager));
        
        console.log("ProxyManager registered in AddressProvider with name: ProxyManager");
        console.log("========================================");
        
        vm.stopBroadcast();
    }
}

