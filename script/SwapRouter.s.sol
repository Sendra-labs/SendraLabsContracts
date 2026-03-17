// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { UniswapLib } from "../src/lib/uniswap/Uniswap.lib.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Script unificado: deploy + executeSwap
 *
 * Uso:
 *   forge script script/SwapRouter.s.sol --broadcast --rpc-url <RPC>
 *
 * Env vars (opcionales):
 *   PRIVATE_KEY o ADMIN1_PRIVATE_KEY  - Clave privada (con o sin 0x)
 *   RUN_SWAP     - "1" para ejecutar swap después del deploy
 *   SWAP_ROUTER  - Si existe, solo ejecuta swap (no despliega)
 *
 * Params del swap (modifica las variables abajo):
 */
contract SwapRouterScript is Script {

    address constant UNIVERSAL_ROUTER = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;

    // --- Params del swap (modifica aquí) ---
    address TOKEN_IN   = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH Arbitrum
    address TOKEN_OUT  = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC Arbitrum
    uint256 AMOUNT_IN  = 0.01 ether;
    uint256 AMOUNT_OUT_MIN = 0;
    UniswapLib.Protocol PROTOCOL = UniswapLib.Protocol.UniswapV2;
    uint24 FEE_TIER = 3000;
    address POOL_OR_PAIR = address(0);
    address POOL_CURRENCY0 = address(0);
    address POOL_CURRENCY1 = address(0);
    uint24 POOL_FEE = 3000;
    int24 POOL_TICK_SPACING = 60;
    IHooks POOL_HOOKS = IHooks(address(0));

    function setUp() public {}

    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env (hex, con o sin 0x)");
    }

    function run() public {
        uint256 pk = _getPrivateKey();
        vm.startBroadcast(pk);

        address swapRouterAddr = vm.envOr("SWAP_ROUTER", address(0));

        if (swapRouterAddr == address(0)) {
            SwapRouter swapRouter = new SwapRouter(UNIVERSAL_ROUTER);
            swapRouterAddr = address(swapRouter);
            console.log("SwapRouter desplegado:", swapRouterAddr);
        }

        if (vm.envOr("RUN_SWAP", uint256(0)) == 1) {
            _executeSwap(swapRouterAddr, vm.addr(pk));
        }

        vm.stopBroadcast();
    }

    function _executeSwap(address swapRouterAddr, address recipient) internal {
        UniswapLib.SwapInput memory swapInput = _buildSwapInput(recipient);

        IERC20(TOKEN_IN).transfer(swapRouterAddr, AMOUNT_IN);
        SwapRouter(swapRouterAddr).executeSwap(swapInput);

        console.log("Swap ejecutado. Recipient:", recipient);
    }

    function _buildSwapInput(address recipient) internal view returns (UniswapLib.SwapInput memory) {
        UniswapLib.SwapInstruction[] memory instructions = new UniswapLib.SwapInstruction[](1);
        instructions[0] = UniswapLib.SwapInstruction({
            protocol: PROTOCOL,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            amountIn: AMOUNT_IN,
            amountOut: AMOUNT_OUT_MIN,
            poolOrPair: POOL_OR_PAIR,
            fee: FEE_TIER,
            poolKey: _buildPoolKey()
        });
        return UniswapLib.SwapInput({
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            swapInstructions: instructions,
            amountIn0: AMOUNT_IN,
            to: recipient
        });
    }

    function _buildPoolKey() internal view returns (PoolKey memory) {
        if (PROTOCOL != UniswapLib.Protocol.UniswapV4) {
            return PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(0)),
                fee: 0,
                tickSpacing: 0,
                hooks: IHooks(address(0))
            });
        }
        address c0 = POOL_CURRENCY0;
        address c1 = POOL_CURRENCY1;
        if (uint160(c0) > uint160(c1)) (c0, c1) = (c1, c0);
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: POOL_FEE,
            tickSpacing: POOL_TICK_SPACING,
            hooks: POOL_HOOKS
        });
    }
}
