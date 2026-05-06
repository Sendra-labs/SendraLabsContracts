// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { UniswapLib } from "../src/lib/uniswap/Uniswap.lib.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/**
 * Script: Orchestrator con configs separadas para provide y withdraw
 *
 * COMANDOS:
 *   # PROVEER liquidez (pool WBTC/USDT)
 *   forge script script/OrchestratorConfig.s.sol:OrchestratorConfigScript --broadcast --rpc-url arbitrum
 *
 *   # CERRAR posición (withdraw + collect fees)
 *   UNI_ID=<tokenId> POSITION_ID=<positionId> RUN_WITHDRAW=1 forge script script/OrchestratorConfig.s.sol:OrchestratorConfigScript --broadcast --rpc-url arbitrum
 *
 * Env: ADMIN1_PRIVATE_KEY o PRIVATE_KEY en .env
 */
contract OrchestratorConfigScript is Script {

    address constant ADDRESS_PROVIDER = 0x73836d093005Dafeb3446c6DB10f325a52ea6f0E;
    address constant LIQUIDITY_ORCHESTRATOR = 0x9bfA65B3A263dac7D678c1e46d8DeD6A62CDAfF2;

    // --- Tokens ---
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;

    // ============ CONFIG: provideLiquidity() - Pool USDC/WETH ============
    // Quote: 45526 USDC total. swap0: USDC directo. swap1: 3 inst (USDC->WETH + USDC->GMX->WETH)
    uint256 AMOUNT_USDC_DIRECT = 0;       // swap0: USDC sin swap (0 = todo va por swap1)
    uint256 AMOUNT_USDC_INST0 = 13_657;   // swap1 inst0: USDC->WETH (route[0])
    uint256 AMOUNT_USDC_INST1 = 31_869;   // swap1 inst1: USDC->GMX (route[1])
    uint256 AMOUNT_GMX_INST2 = 4_925_771_328_652_477; // swap1 inst2: GMX->WETH (output esperado de inst1, ~0.5% slippage)
    // Pool USDC/WETH: token0=WETH, token1=USDC. Output total 3 inst: ~21336700504255 WETH
    uint256 AMOUNT0 = 21_230_017_001_733; // WETH (token0): min output swap1 (slippage 0.5%)
    uint256 AMOUNT1 = 0;                  // USDC (token1): swap0 vacio = 0
    int24 TICK_LOWER = -199_600;          // Ajustar segun pool USDC/WETH
    int24 TICK_UPPER = -199_500;
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

        if (vm.envOr("RUN_WITHDRAW", uint256(0)) == 1) {
            _withdraw(vm.addr(pk));
        } else {
            _provide();
        }

        vm.stopBroadcast();
    }

    function _provide() internal {
        (UniswapLib.SwapInput memory s0, UniswapLib.SwapInput memory s1) = _getProvideSwapInputs();
        uint256 total0 = s0.amountIn0;
        uint256 total1 = s1.tokenIn == s0.tokenIn ? s1.amountIn0 : 0;
        IERC20(s0.tokenIn).approve(LIQUIDITY_ORCHESTRATOR, total0 + total1);
        if (s1.tokenIn != s0.tokenIn) {
            IERC20(s1.tokenIn).approve(LIQUIDITY_ORCHESTRATOR, s1.amountIn0);
        }

        UniswapLib.ExecuteProvideLiquidityInput memory input = _buildProvideInput(s0, s1);
        LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).provideLiquidity(input);

        console.log("provideLiquidity OK. Recipient:", RECIPIENT);
    }

    function _withdraw(address broadcaster) internal {
        INonfungiblePositionManager nftManager = INonfungiblePositionManager(
            AddressProvider(ADDRESS_PROVIDER).getAddress("UniswapNFTPositionManager")
        );

        uint256 positionId = vm.envOr("POSITION_ID", uint256(1));
        uint128 uniId = uint128(vm.envOr("UNI_ID", uint256(0)));
        require(uniId != 0, "UNI_ID required para withdraw");

        nftManager.approve(LIQUIDITY_ORCHESTRATOR, uniId);

        UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory input = _buildWithdrawInput(uniId, positionId, broadcaster);
        uint256 amountOut = LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).withdrawLiquidityAndCollectFees(input);

        console.log("withdrawLiquidityAndCollectFees OK. USDC out:", amountOut);
    }

    /// @dev Path 0: USDC directo (no swap) - token1 del pool
    function _getProvideSwap0Instructions() internal pure returns (UniswapLib.SwapInstruction[] memory) {
        return new UniswapLib.SwapInstruction[](0);
    }

    /// @dev Path 1: 3 instrucciones según quote (2 rutas agregadas)
    ///      Inst0: USDC->WETH (13657, fee 500) - route[0]
    ///      Inst1: USDC->GMX (31869, fee 10000) - route[1] step0
    ///      Inst2: GMX->WETH (0, fee 500) - route[1] step1, amountIn=0 = output prev
    function _getProvideSwap1Instructions() internal view returns (UniswapLib.SwapInstruction[] memory) {
        UniswapLib.SwapInstruction[] memory inst = new UniswapLib.SwapInstruction[](3);
        inst[0] = _swapInst(UniswapLib.Protocol.UniswapV3, USDC, WETH, AMOUNT_USDC_INST0, 0, 500, address(0));
        inst[1] = _swapInst(UniswapLib.Protocol.UniswapV3, USDC, GMX, AMOUNT_USDC_INST1, 0, 10_000, address(0));
        inst[2] = _swapInst(UniswapLib.Protocol.UniswapV3, GMX, WETH, AMOUNT_GMX_INST2, 0, 500, address(0));
        return inst;
    }

    function _getProvideSwapInputs() internal view returns (UniswapLib.SwapInput memory, UniswapLib.SwapInput memory) {
        UniswapLib.SwapInstruction[] memory inst0 = _getProvideSwap0Instructions();
        UniswapLib.SwapInstruction[] memory inst1 = _getProvideSwap1Instructions();
        require(inst1.length > 0, "Swap1 instructions vacias");

        UniswapLib.SwapInput memory s0;
        if (inst0.length == 0) {
            // swap0 vacio: USDC directo (tokenIn=tokenOut => no swap)
            s0 = UniswapLib.SwapInput({
                tokenIn: USDC,
                tokenOut: USDC,
                swapInstructions: inst0,
                amountIn0: AMOUNT_USDC_DIRECT,
                to: address(0)
            });
        } else {
            s0 = UniswapLib.SwapInput({
                tokenIn: inst0[0].tokenIn,
                tokenOut: inst0[inst0.length - 1].tokenOut,
                swapInstructions: inst0,
                amountIn0: inst0[0].amountIn,
                to: address(0)
            });
        }

        // amountIn0 = suma de amountIn de instrucciones que usan tokenIn inicial
        uint256 totalIn = 0;
        address tokenIn = inst1[0].tokenIn;
        for (uint256 i = 0; i < inst1.length; i++) {
            if (inst1[i].tokenIn == tokenIn) totalIn += inst1[i].amountIn;
        }
        UniswapLib.SwapInput memory s1 = UniswapLib.SwapInput({
            tokenIn: inst1[0].tokenIn,
            tokenOut: inst1[inst1.length - 1].tokenOut,
            swapInstructions: inst1,
            amountIn0: totalIn,
            to: address(0)
        });
        return (s0, s1);
    }

    function _swapInst(
        UniswapLib.Protocol p,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint24 fee,
        address poolOrPair
    ) internal pure returns (UniswapLib.SwapInstruction memory) {
        return UniswapLib.SwapInstruction({
            protocol: p,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            poolOrPair: poolOrPair,
            fee: fee,
            poolKey: _emptyPoolKey()
        });
    }

    /// @dev Para swaps V4: requiere PoolKey (currency0 < currency1 por address)
    function _swapInstV4(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint24 fee,
        PoolKey memory poolKey
    ) internal pure returns (UniswapLib.SwapInstruction memory) {
        return UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV4,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            poolOrPair: address(0),
            fee: fee,
            poolKey: poolKey
        });
    }

    /// @dev Construye PoolKey para V4. currency0 y currency1 deben estar ordenados (addr menor primero)
    function _buildPoolKey(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing
    ) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
    }

    function _buildProvideInput(
        UniswapLib.SwapInput memory swapInput0,
        UniswapLib.SwapInput memory swapInput1
    ) internal view returns (UniswapLib.ExecuteProvideLiquidityInput memory) {
        // Pool USDC/WETH: token0=WETH (addr<USDC), token1=USDC
        UniswapLib.ProvideLiquidityInput memory liqInput = UniswapLib.ProvideLiquidityInput({
            protocol: UniswapLib.Protocol.UniswapV3,
            token0: WETH,
            token1: USDC,
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

    /// @dev Define aquí las instrucciones de swap para withdraw path 0 (token0 del pool -> token final, ej. USDC)
    function _getWithdrawSwap0Instructions() internal pure returns (UniswapLib.SwapInstruction[] memory) {
        UniswapLib.SwapInstruction[] memory inst = new UniswapLib.SwapInstruction[](1);
        inst[0] = _swapInst(UniswapLib.Protocol.UniswapV3, WBTC, USDC, 0, 0, 500, 0x599bB1269B71625dA7761ba79A228230c8354C55);
        return inst;
    }

    /// @dev Define aquí las instrucciones de swap para withdraw path 1 (token1 del pool -> token final)
    function _getWithdrawSwap1Instructions() internal pure returns (UniswapLib.SwapInstruction[] memory) {
        UniswapLib.SwapInstruction[] memory inst = new UniswapLib.SwapInstruction[](1);
        inst[0] = _swapInst(UniswapLib.Protocol.UniswapV3, USDT, USDC, 0, 0, 500, address(0));
        // Ejemplo multi-hop USDT->WETH->USDC:
        // inst = new SwapInstruction[](2);
        // inst[0] = _swapInst(..., USDT, WETH, 0, 0, 500, 0);
        // inst[1] = _swapInst(..., WETH, USDC, 0, 0, 100, 0);
        return inst;
    }

    function _buildWithdrawInput(uint128 uniId, uint256 positionId, address user) internal view returns (UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory) {
        UniswapLib.SwapInstruction[] memory inst0 = _getWithdrawSwap0Instructions();
        UniswapLib.SwapInstruction[] memory inst1 = _getWithdrawSwap1Instructions();
        require(inst0.length > 0 && inst1.length > 0, "Withdraw swap instructions vacias");

        UniswapLib.SwapInput memory swapInput0 = UniswapLib.SwapInput({
            tokenIn: inst0[0].tokenIn,
            tokenOut: inst0[inst0.length - 1].tokenOut,
            swapInstructions: inst0,
            amountIn0: 0,
            to: address(0)
        });
        UniswapLib.SwapInput memory swapInput1 = UniswapLib.SwapInput({
            tokenIn: inst1[0].tokenIn,
            tokenOut: inst1[inst1.length - 1].tokenOut,
            swapInstructions: inst1,
            amountIn0: 0,
            to: address(0)
        });

        UniswapLib.WithdrawLiquidityInput memory withdrawInput = UniswapLib.WithdrawLiquidityInput({
            uniId: uniId,
            positionId: positionId,
            user: user
        });

        return UniswapLib.ExecuteWithdrawLiquidityAndCollectFees({
            withdrawLiquidityInput: withdrawInput,
            swapInput0: swapInput0,
            swapInput1: swapInput1
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
