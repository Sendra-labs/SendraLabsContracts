// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";

contract RegisterMarketNeutral is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");
    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;
    address public constant MARKET_NEUTRAL = 0x9223482EF1dC62B4581B28d39e9bCcA86dE9983d;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        
        AddressProvider addressProvider = AddressProvider(ADDRESS_PROVIDER);
        addressProvider.setAddress("MarketNeutral", MARKET_NEUTRAL);
        
        vm.stopBroadcast();
    }
}

