// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { PairTrading } from "../src/core/bundles/executors/PairTrading.sol";

contract DeployMarketNeutral is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");
    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;

    function setUp() public {}

    function run() public {
        require(ADDRESS_PROVIDER != address(0), "AddressProvider address not set");
        
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);
        
        PairTrading pairTrading = new PairTrading(ADDRESS_PROVIDER);
        AddressProvider addressProvider = AddressProvider(ADDRESS_PROVIDER);
        addressProvider.setAddress("PairTrading", address(pairTrading));
        
        vm.stopBroadcast();
    }
}

