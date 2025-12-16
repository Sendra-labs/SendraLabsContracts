// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { MarketNeutral } from "../src/core/bundles/executors/MarketNeutral.sol";

contract DeployMarketNeutral is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");
    
    // Dirección del AddressProvider ya desplegado (cambiar según tu deployment)
    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;

    function setUp() public {}

    function run() public {
        // Verificar que AddressProvider esté configurado
        require(ADDRESS_PROVIDER != address(0), "AddressProvider address not set");
        
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        
        console.log("========================================");
        console.log("Deploying MarketNeutral contract...");
        console.log("========================================");
        
        // Desplegar MarketNeutral
        MarketNeutral marketNeutral = new MarketNeutral(ADDRESS_PROVIDER);
        
        console.log("MarketNeutral deployed at:", address(marketNeutral));
        
        // Registrar en AddressProvider
        AddressProvider addressProvider = AddressProvider(ADDRESS_PROVIDER);
        addressProvider.setAddress("MarketNeutral", address(marketNeutral));
        
        console.log("MarketNeutral registered in AddressProvider with name: MarketNeutral");
        console.log("========================================");
        
        vm.stopBroadcast();
    }
}

