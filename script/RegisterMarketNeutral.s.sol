// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";

contract RegisterMarketNeutral is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");
    
    // Dirección del AddressProvider ya desplegado
    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;
    
    // Dirección del contrato MarketNeutral a registrar
    address public constant MARKET_NEUTRAL = 0x9223482EF1dC62B4581B28d39e9bCcA86dE9983d;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        
        console.log("========================================");
        console.log("Registering MarketNeutral in AddressProvider...");
        console.log("========================================");
        console.log("AddressProvider:", ADDRESS_PROVIDER);
        console.log("MarketNeutral:", MARKET_NEUTRAL);
        
        // Registrar en AddressProvider
        AddressProvider addressProvider = AddressProvider(ADDRESS_PROVIDER);
        addressProvider.setAddress("MarketNeutral", MARKET_NEUTRAL);
        
        console.log("MarketNeutral registered successfully!");
        console.log("Name: MarketNeutral");
        console.log("Address:", MARKET_NEUTRAL);
        console.log("========================================");
        
        vm.stopBroadcast();
    }
}

