// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { LiquidityManager } from "../src/core/uniswap/executors/LiquidityManager.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { Roles } from "../src/security/Roles.sol";

/**
 * Despliega LiquidityManager (FullMath corregido) y un LiquidityOrchestrator nuevo.
 * El orquestador guarda el manager como immutable, así que hay que desplegarlo después
 * de registrar el manager en el AddressProvider.
 *
 * Desde protocol/:
 *   forge script script/DeployLiquidityOrchestrator.s.sol:DeployLiquidityOrchestrator --rpc-url arbitrum --broadcast
 *
 * Requiere ADMIN1_PRIVATE_KEY o PRIVATE_KEY de un admin del AddressProvider.
 */
contract DeployLiquidityOrchestrator is Script {
    address constant ADDRESS_PROVIDER = 0xaF7A2feFBA6Acc09e62011d0359dC06e0e1245f5;

    function run() public {
        uint256 pk = _getPrivateKey();
        AddressProvider provider = AddressProvider(ADDRESS_PROVIDER);
        Roles roles = Roles(provider.getAddress("Roles"));

        try provider.getAddress("LiquidityManager") returns (address previousManager) {
            console.log("LiquidityManager anterior:", previousManager);
        } catch {
            console.log("LiquidityManager anterior: ninguno");
        }
        try provider.getAddress("LiquidityOrchestrator") returns (address previous) {
            console.log("LiquidityOrchestrator anterior:", previous);
        } catch {
            console.log("LiquidityOrchestrator anterior: ninguno");
        }

        vm.startBroadcast(pk);

        LiquidityManager manager = new LiquidityManager(ADDRESS_PROVIDER);
        provider.setAddress("LiquidityManager", address(manager));

        LiquidityOrchestrator orchestrator = new LiquidityOrchestrator(ADDRESS_PROVIDER);
        roles.allowContract(address(orchestrator), "LiquidityOrchestrator");
        provider.setAddress("LiquidityOrchestrator", address(orchestrator));

        vm.stopBroadcast();

        console.log("LiquidityManager:", address(manager));
        console.log("LiquidityOrchestrator:", address(orchestrator));
        console.log("manager registrado:", provider.getAddress("LiquidityManager"));
        console.log("orquestador registrado:", provider.getAddress("LiquidityOrchestrator"));
        console.log("protocolo:", roles.isProtocolContract(address(orchestrator)));
    }

    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 key) {
            return key;
        } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            return key;
        } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env");
    }
}
