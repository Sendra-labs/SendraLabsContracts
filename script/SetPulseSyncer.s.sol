// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { SendraStorage } from "../src/core/SendraStorage.sol";

/**
 * @notice Registers `pulseSyncer` on SendraStorage. The signer must already be an admin.
 *
 *         PULSE_SYNCER             address authorized to seal/commit the global pulse
 *         HOT_ADMIN1_PRIVATE_KEY   admin that signs
 *         SENDRA_STORAGE           optional; otherwise resolved from ADDRESS_PROVIDER
 *         ADDRESS_PROVIDER         used when SENDRA_STORAGE is unset
 *
 *         forge script script/SetPulseSyncer.s.sol --rpc-url arbitrum --broadcast
 */
contract SetPulseSyncer is Script {
    function run() public {
        address syncer = vm.envAddress("PULSE_SYNCER");
        uint256 pk = vm.envUint("HOT_ADMIN1_PRIVATE_KEY");

        address books = vm.envOr("SENDRA_STORAGE", address(0));
        if (books == address(0)) {
            books = AddressProvider(vm.envAddress("ADDRESS_PROVIDER")).getAddress("SendraStorage");
        }

        vm.startBroadcast(pk);
        SendraStorage(books).setPulseSyncer(syncer);
        vm.stopBroadcast();

        console.log("SendraStorage", books);
        console.log("pulseSyncer", SendraStorage(books).pulseSyncer());
    }
}
