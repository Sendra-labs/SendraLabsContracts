// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { Roles } from "../src/security/Roles.sol";
import { SendraStorage } from "../src/core/SendraStorage.sol";
import { PositionInitializer } from "../src/core/PositionInitializer.sol";

/**
 * @notice Deploys the Sendra core on Robinhood Chain (4663).
 *         COLD_ADMIN1/2/3 are hardware addresses, not keys. HOT_ADMIN1/2/3_PRIVATE_KEY sign
 *         and are admins from the same constructor. The cold wallets never sign this script.
 *         USDG is the chain's dollar and is registered in AddressProvider under the name "USDC".
 *
 *         forge script script/DeployRobinhood.s.sol --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast
 */
contract DeployRobinhood is Script {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    function run() public {
        if (block.chainid != 4663) revert WrongChain();

        address cold1 = vm.envAddress("COLD_ADMIN1");
        address cold2 = vm.envAddress("COLD_ADMIN2");
        address cold3 = vm.envAddress("COLD_ADMIN3");
        uint256 k1 = vm.envUint("HOT_ADMIN1_PRIVATE_KEY");
        uint256 k2 = vm.envUint("HOT_ADMIN2_PRIVATE_KEY");
        uint256 k3 = vm.envUint("HOT_ADMIN3_PRIVATE_KEY");
        address hot1 = vm.addr(k1);
        address hot2 = vm.addr(k2);
        address hot3 = vm.addr(k3);

        vm.startBroadcast(k1);
        Roles roles = new Roles(cold1, cold2, cold3, hot1, hot2, hot3);
        AddressProvider provider = new AddressProvider(address(roles));
        vm.stopBroadcast();

        _vote(provider, k1, k2, k3, "Roles", address(roles), roles, false);
        _vote(provider, k1, k2, k3, "SendraRoles", address(roles), roles, false);
        _vote(provider, k1, k2, k3, "USDC", USDG, roles, false);
        _vote(provider, k1, k2, k3, "WETH", WETH, roles, false);

        vm.startBroadcast(k1);
        SendraStorage books = new SendraStorage(address(roles));
        vm.stopBroadcast();
        _vote(provider, k1, k2, k3, "SendraStorage", address(books), roles, false);

        vm.startBroadcast(k1);
        PositionInitializer initializer = new PositionInitializer(address(provider));
        vm.stopBroadcast();
        _vote(provider, k1, k2, k3, "PositionInitializer", address(initializer), roles, true);

        console.log("Roles", address(roles));
        console.log("AddressProvider", address(provider));
        console.log("SendraStorage", address(books));
        console.log("PositionInitializer", address(initializer));
        console.log("USDC", USDG);
        console.log("WETH", WETH);
        console.log("cold1", cold1);
        console.log("cold2", cold2);
        console.log("cold3", cold3);
        console.log("hot1", hot1);
        console.log("hot2", hot2);
        console.log("hot3", hot3);
    }

    function _vote(
        AddressProvider provider,
        uint256 k1,
        uint256 k2,
        uint256 k3,
        string memory name,
        address target,
        Roles roles,
        bool allow
    ) internal {
        uint256[3] memory keys = [k1, k2, k3];
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(keys[i]);
            provider.proposeAddress(name, target);
            if (allow) roles.allowContract(target, name);
            vm.stopBroadcast();
        }
    }

    error WrongChain();
}
