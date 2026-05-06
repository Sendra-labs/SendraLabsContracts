// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";

import { Roles } from "../src/security/Roles.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";

import { LiquidityManager } from "../src/core/uniswap/executors/LiquidityManager.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";

/**
 * DeployUniswapLP
 *
 * Despliega SOLO la parte de Uniswap LP (LiquidityManager, SwapRouter, LiquidityOrchestrator),
 * registra las addresses en un AddressProvider ya existente y whitelistea en Roles lo mínimo
 * para que SendraStorage acepte escrituras del orchestrator (onlyProtocol).
 *
 * Command:
 * forge script script/DeployUniswapLP.s.sol:DeployUniswapLP --broadcast --rpc-url arbitrum
 *
 * Env:
 *   ADMIN1_PRIVATE_KEY o PRIVATE_KEY (tiene que ser un admin en Roles)
 */
contract DeployUniswapLP is Script {
    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env");
    }

    // --- Existing deployment (from your logs) ---
    address public constant ROLES = 0x45Aa151522929Ca5536d9788aD785bd2164844CF;
    address public constant ADDRESS_PROVIDER = 0x5cfDbe50269C22D470a29eD6BC4C1952b7B3eb4B;

    // --- Uniswap (Arbitrum) ---
    address public constant UNISWAP_UNIVERSAL_ROUTER = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNISWAP_NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    Roles public roles = Roles(ROLES);
    AddressProvider public addressProvider = AddressProvider(ADDRESS_PROVIDER);

    LiquidityManager public liquidityManager;
    SwapRouter public swapRouter;
    LiquidityOrchestrator public liquidityOrchestrator;

    function run() public {
        uint256 pk = _getPrivateKey();
        vm.startBroadcast(pk);

        // 0) Ensure external Uniswap addresses exist in AddressProvider (idempotent overwrite)
        _setAndCheck("UniswapV3Factory", UNISWAP_V3_FACTORY);
        _setAndCheck("UniswapNFTPositionManager", UNISWAP_NFT_POSITION_MANAGER);
        _setAndCheck("UniswapUniversalRouter", UNISWAP_UNIVERSAL_ROUTER);

        // 1) Deploy + register LiquidityManager and SwapRouter first
        liquidityManager = new LiquidityManager(address(addressProvider));
        swapRouter = new SwapRouter(UNISWAP_UNIVERSAL_ROUTER);
        _setAndCheck("LiquidityManager", address(liquidityManager));
        _setAndCheck("SwapRouter", address(swapRouter));

        // 2) Deploy orchestrator AFTER router/manager are registered (important if constructor caches addresses)
        liquidityOrchestrator = new LiquidityOrchestrator(address(addressProvider));
        _setAndCheck("LiquidityOrchestrator", address(liquidityOrchestrator));

        // 3) Whitelist protocol writers (SendraStorage.onlyProtocol)
        roles.allowContract(address(liquidityOrchestrator), "LiquidityOrchestrator");

        _printSummary();

        vm.stopBroadcast();
    }

    function _set(string memory key, address value) internal {
        addressProvider.setAddress(key, value);
    }

    function _get(string memory key) internal view returns (address) {
        return addressProvider.addressMap(key);
    }

    function _setAndCheck(string memory key, address value) internal {
        address beforeValue = _get(key);
        _set(key, value);
        address afterValue = _get(key);
        require(afterValue == value, "AddressProvider: setAddress failed");
    }

    function _printSummary() internal view {
        console.log("================================");
        console.log("Roles -------------------->", address(roles));
        console.log("AddressProvider ---------->", address(addressProvider));
        console.log("UniswapV3Factory --------->", UNISWAP_V3_FACTORY);
        console.log("UniswapNFTPositionManager ->", UNISWAP_NFT_POSITION_MANAGER);
        console.log("UniswapUniversalRouter --->", UNISWAP_UNIVERSAL_ROUTER);
        console.log("LiquidityManager --------->", address(liquidityManager));
        console.log("SwapRouter --------------->", address(swapRouter));
        console.log("LiquidityOrchestrator ---->", address(liquidityOrchestrator));
        console.log("== AddressProvider snapshot ==");
        console.log("LiquidityManager(key) ---->", _get("LiquidityManager"));
        console.log("SwapRouter(key) ---------->", _get("SwapRouter"));
        console.log("LiquidityOrchestrator(key)->", _get("LiquidityOrchestrator"));
        console.log("================================");
    }
}

