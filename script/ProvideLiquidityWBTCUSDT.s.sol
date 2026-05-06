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
 * Script para REPRODUCIR el provideLiquidity WBTC/USDT que falla en frontend.
 * Params exactos del frontend (caso que falla con "Price slippage check").
 *
 * COMANDO:
 *   forge script script/ProvideLiquidityWBTCUSDT.s.sol:ProvideLiquidityWBTCUSDTScript --broadcast --rpc-url arbitrum
 *
 * Opcional (solo simular, no broadcast):
 *   forge script script/ProvideLiquidityWBTCUSDT.s.sol:ProvideLiquidityWBTCUSDTScript --rpc-url arbitrum -vvvv
 *
 * Env: ADMIN1_PRIVATE_KEY o PRIVATE_KEY en .env
 */
contract ProvideLiquidityWBTCUSDTScript is Script {

    address constant ADDRESS_PROVIDER = 0x73836d093005Dafeb3446c6DB10f325a52ea6f0E;
    address constant LIQUIDITY_ORCHESTRATOR = 0x8EB347dc8960Dda7279D13859C68B909cdB8f71a;

    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // --- Params exactos del frontend (provideLiquidityInput) ---
    uint256 constant AMOUNT0 = 0;                // WBTC - single-sided USDT
    uint256 constant AMOUNT1 = 2659634;          // USDT (6 decimals)
    int24 constant TICK_LOWER = 64570;
    int24 constant TICK_UPPER = 65600;
    uint24 constant POOL_FEE = 500;
    address constant RECIPIENT = 0x8224D492eC12564EdEbe060a7fFD76296760aD4e;
    bool constant IS_SENDRA_RECIPIENT = false;

    // --- Params swap0: USDC -> USDT ---
    uint256 constant AMOUNT_IN_SWAP0 = 3000000;  // USDC (3 USDC)
    uint24 constant FEE_SWAP0 = 100;             // 0.01%

    // --- Params swap1: sin swap (tokenIn=tokenOut=WBTC, amountIn0=0)

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

        IERC20(USDC).approve(LIQUIDITY_ORCHESTRATOR, AMOUNT_IN_SWAP0);

        UniswapLib.ExecuteProvideLiquidityInput memory input = _buildInput();
        LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).provideLiquidity(input);

        console.log("provideLiquidity WBTC/USDT OK. Recipient:", RECIPIENT);

        vm.stopBroadcast();
    }

    function _buildInput() internal pure returns (UniswapLib.ExecuteProvideLiquidityInput memory) {
        UniswapLib.SwapInstruction[] memory inst0 = new UniswapLib.SwapInstruction[](1);
        inst0[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: USDC,
            tokenOut: USDT,
            amountIn: AMOUNT_IN_SWAP0,
            amountOut: 0,
            poolOrPair: address(0),
            fee: FEE_SWAP0,
            poolKey: _emptyPoolKey()
        });

        // swap1: sin swap (solo USDT; rango single-sided)
        UniswapLib.SwapInstruction[] memory inst1 = new UniswapLib.SwapInstruction[](0);

        UniswapLib.SwapInput memory swapInput0 = UniswapLib.SwapInput({
            tokenIn: USDC,
            tokenOut: USDT,
            swapInstructions: inst0,
            amountIn0: AMOUNT_IN_SWAP0,
            to: address(0)
        });
        UniswapLib.SwapInput memory swapInput1 = UniswapLib.SwapInput({
            tokenIn: WBTC,
            tokenOut: WBTC,
            swapInstructions: inst1,
            amountIn0: 0,
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
