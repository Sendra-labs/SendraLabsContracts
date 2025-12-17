// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { Roles } from "../src/security/Roles.sol";
import { ClosePositionCallbacks } from "../src/core/bundles/executors/callbacks/ClosePositionCallbacks.sol";

contract DeployCallback is Script {

    uint256 public ADMIN1_PRIVATE_KEY = vm.envUint("ADMIN1_PRIVATE_KEY");

    AddressProvider public addressProvider;
    Roles public roles;
    ClosePositionCallbacks public closePositionCallbacks;

    address public constant ADDRESS_PROVIDER = 0x81806092f74bEd8B100c29517Fbb5765fBe592f1;
    address public constant ROLES = 0xa160A99ec745FC1E3Aa6b144971225596a26BfB4;

    function setUp() public {}
    
    function run() public {
        vm.startBroadcast(ADMIN1_PRIVATE_KEY);

        addressProvider = AddressProvider(ADDRESS_PROVIDER);
        roles = Roles(ROLES);
        
        closePositionCallbacks = new ClosePositionCallbacks(address(addressProvider));
        
        scriptSetAddresses(address(closePositionCallbacks), "ClosePositionCallbacks");
        scriptAllowContract(address(closePositionCallbacks), "ClosePositionCallbacks");

        vm.stopBroadcast();
    }

    function scriptAllowContract(address _contract, string memory _name) public {
        roles.allowContract(_contract, _name);
    }
    
    function scriptSetAddresses(address _address, string memory _name) public {
        addressProvider.setAddress(_name, _address);
    }
}
