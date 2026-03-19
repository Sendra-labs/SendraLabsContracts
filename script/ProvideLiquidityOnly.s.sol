// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { UniswapLib } from "../src/lib/uniswap/Uniswap.lib.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Script: Solo provideLiquidity (sin deploy)
 * USDC -> swap0 (USDT) + swap1 (WBTC) -> pool WBTC/USDT
 *
 * COMANDO:
 *   forge script script/ProvideLiquidityOnly.s.sol --broadcast --rpc-url arbitrum
 *
 * Env: ADMIN1_PRIVATE_KEY o PRIVATE_KEY en .env
 */
contract ProvideLiquidityOnlyScript is Script {

    // --- Contratos desplegados ---
    address constant LIQUIDITY_ORCHESTRATOR = 0xc9085c56D807bBfd6FA7d82e74a19EE9572b2b55;

    // --- Tokens ---
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // --- Params (config + quotes) ---
    // swapInput0: USDC -> USDT (quote: 498985 in -> 498931 out, minAmount 496436)
    uint256 AMOUNT_USDC_SWAP0 = 499_226;
    uint256 AMOUNT_OUT_MIN0 = 496_436;  // minAmount de quote USDC->USDT

    // swapInput1: USDC -> WBTC (quote: 501015 in -> 714 out, minAmount 710)
    uint256 AMOUNT_USDC_SWAP1 = 500_774;
    uint256 AMOUNT_OUT_MIN1 = 710;  // minAmount de quote USDC->WBTC

    uint24 FEE_TIER_SWAP = 500;

    // provideLiquidityInput: DEBEN coincidir con los outputs de los swaps
    // Swap0: ~498840 USDT | Swap1: 714 WBTC (trace real)
    uint256 AMOUNT0 = 714;      // WBTC recibido de swap1
    uint256 AMOUNT1 = 498_840;  // USDT recibido de swap0
    int24 TICK_LOWER = 109_750;
    int24 TICK_UPPER = 113_400;
    uint24 POOL_FEE = 500;
    address RECIPIENT = 0x7F4C831de10684f85867899708cB49FfbF4983B9;
    bool IS_SENDRA_RECIPIENT = false;

    function setUp() public {}

    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env");
    }

    function run() public {
        uint256 pk = _getPrivateKey();
        vm.addr(pk);
        vm.startBroadcast(pk);

        uint256 totalUsdc = AMOUNT_USDC_SWAP0 + AMOUNT_USDC_SWAP1;
        IERC20(USDC).approve(LIQUIDITY_ORCHESTRATOR, totalUsdc);

        UniswapLib.ExecuteProvideLiquidityInput memory input = _buildInput();
        LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).provideLiquidity(input);

        console.log("provideLiquidity ejecutado. Recipient:", RECIPIENT);
        vm.stopBroadcast();
    }

    function _buildInput() internal view returns (UniswapLib.ExecuteProvideLiquidityInput memory) {
        UniswapLib.SwapInstruction[] memory inst0 = new UniswapLib.SwapInstruction[](1);
        inst0[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: USDC,
            tokenOut: USDT,
            amountIn: AMOUNT_USDC_SWAP0,
            amountOut: AMOUNT_OUT_MIN0,
            poolOrPair: address(0),
            fee: FEE_TIER_SWAP,
            poolKey: _emptyPoolKey()
        });

        UniswapLib.SwapInstruction[] memory inst1 = new UniswapLib.SwapInstruction[](1);
        inst1[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: USDC,
            tokenOut: WBTC,
            amountIn: AMOUNT_USDC_SWAP1,
            amountOut: AMOUNT_OUT_MIN1,
            poolOrPair: address(0),
            fee: FEE_TIER_SWAP,
            poolKey: _emptyPoolKey()
        });

        UniswapLib.SwapInput memory swapInput0 = UniswapLib.SwapInput({
            tokenIn: USDC,
            tokenOut: USDT,
            swapInstructions: inst0,
            amountIn0: AMOUNT_USDC_SWAP0,
            to: address(0)
        });
        UniswapLib.SwapInput memory swapInput1 = UniswapLib.SwapInput({
            tokenIn: USDC,
            tokenOut: WBTC,
            swapInstructions: inst1,
            amountIn0: AMOUNT_USDC_SWAP1,
            to: address(0)
        });

        UniswapLib.ProvideLiquidityInput memory liqInput = UniswapLib.ProvideLiquidityInput({
            protocol: UniswapLib.Protocol.UniswapV3,
            token0: WBTC,
            token1: USDT,
            recipient: RECIPIENT,
            user: RECIPIENT,
            amount0: AMOUNT0,
            amount1: AMOUNT1,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            fee: POOL_FEE
        });

        return UniswapLib.ExecuteProvideLiquidityInput({
            swapInput0: swapInput0,
            swapInput1: swapInput1,
            provideLiquidityInput: liqInput,
            isSendraRecipient: IS_SENDRA_RECIPIENT
        });
    }

    function _emptyPoolKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });
    }
}
