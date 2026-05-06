// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { UniswapLib } from "../src/lib/uniswap/Uniswap.lib.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendraStorage } from "../src/core/SendraStorage.sol";
import { SendraLib } from "../src/lib/Sendra.lib.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/**
 * Script: provideLiquidity y opcionalmente withdraw inmediato
 * USDC -> swap0 (WETH) + swap1 (WBTC) -> pool WBTC/WETH
 *
 * COMANDOS:
 *   # Solo provide
 *   forge script script/ProvideLiquidityOnly.s.sol:ProvideLiquidityOnlyScript --broadcast --rpc-url arbitrum
 *
 *   # Provide + withdraw (2 sesiones broadcast: provide primero, luego approve+withdraw)
 *   RUN_PROVIDE_AND_WITHDRAW=1 forge script script/ProvideLiquidityOnly.s.sol:ProvideLiquidityOnlyScript --broadcast --rpc-url arbitrum
 *
 *   # Solo withdraw (si provide+withdraw falla, ejecutar provide, luego:)
 *   # POSITION_ID=16 UNI_ID=5381677 RUN_WITHDRAW_ONLY=1 forge script ...
 *   RUN_WITHDRAW_ONLY=1 forge script script/ProvideLiquidityOnly.s.sol:ProvideLiquidityOnlyScript --broadcast --rpc-url arbitrum
 *
 * Env: ADMIN1_PRIVATE_KEY o PRIVATE_KEY en .env
 */
contract ProvideLiquidityOnlyScript is Script {

    // --- Contratos desplegados ---
    address constant ADDRESS_PROVIDER = 0x73836d093005Dafeb3446c6DB10f325a52ea6f0E;
    address constant LIQUIDITY_ORCHESTRATOR = 0x9bfA65B3A263dac7D678c1e46d8DeD6A62CDAfF2;

    // --- Tokens ---
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // --- Params (config frontend) ---
    // swapInput0: USDC -> WETH
    uint256 AMOUNT_USDC_SWAP0 = 50_000;
    uint256 AMOUNT_OUT_MIN0 = 0;

    // swapInput1: USDC -> WBTC
    uint256 AMOUNT_USDC_SWAP1 = 50_000;
    uint256 AMOUNT_OUT_MIN1 = 0;

    uint24 FEE_TIER_SWAP = 500;

    // provideLiquidityInput (pool WBTC/WETH)
    // AMOUNT1: ~98% del frontend para que amount1Min (95% en contrato) pase con ratio del pool
    uint256 AMOUNT0 = 70;               // WBTC
    uint256 AMOUNT1 = 22_947_734_358_130; // WETH (~98% de 23.4e12, conservador para slippage 5%)
    int24 TICK_LOWER = 263_300;
    int24 TICK_UPPER = 266_950;
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

        if (vm.envOr("RUN_WITHDRAW_ONLY", uint256(0)) == 1) {
            _withdrawOnly(vm.addr(pk));
        } else if (vm.envOr("RUN_PROVIDE_AND_WITHDRAW", uint256(0)) == 1) {
            _provideAndWithdraw(pk);
        } else {
            _provideOnly();
        }

        vm.stopBroadcast();
    }

    function _provideOnly() internal {
        uint256 totalUsdc = AMOUNT_USDC_SWAP0 + AMOUNT_USDC_SWAP1;
        IERC20(USDC).approve(LIQUIDITY_ORCHESTRATOR, totalUsdc);

        UniswapLib.ExecuteProvideLiquidityInput memory input = _buildInput();
        LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).provideLiquidity(input);

        console.log("provideLiquidity ejecutado. Recipient:", RECIPIENT);
    }

    /// @param pk Private key del broadcaster (owner del NFT tras provide)
    function _provideAndWithdraw(uint256 pk) internal {
        address broadcaster = vm.addr(pk);
        SendraStorage sendraStorage = SendraStorage(AddressProvider(ADDRESS_PROVIDER).getAddress("SendraStorage"));
        INonfungiblePositionManager nftManager = INonfungiblePositionManager(AddressProvider(ADDRESS_PROVIDER).getAddress("UniswapNFTPositionManager"));

        uint256 totalPositionsBefore = sendraStorage.getUser(broadcaster).totalPositions;

        // 1. Provide liquidity (Orchestrator envia NFT a msg.sender = broadcaster)
        uint256 totalUsdc = AMOUNT_USDC_SWAP0 + AMOUNT_USDC_SWAP1;
        IERC20(USDC).approve(LIQUIDITY_ORCHESTRATOR, totalUsdc);

        UniswapLib.ExecuteProvideLiquidityInput memory provideInput = _buildInput();
        LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).provideLiquidity(provideInput);

        uint256 positionId = sendraStorage.getUser(broadcaster).totalPositions;
        require(positionId > totalPositionsBefore, "No new position created");

        SendraLib.Position memory position = sendraStorage.getUserPositionById(broadcaster, positionId);
        require(position.positionData.length > 9, "Position data missing tokenId");

        uint256 tokenId = abi.decode(position.positionData[9], (uint256));
        uint128 uniId = uint128(tokenId);

        console.log("provideLiquidity OK. positionId:", positionId, "uniId:", uniId);

        // 2. Nueva sesion de broadcast: approve + withdraw (evita fallo approve en misma sesion)
        vm.stopBroadcast();
        vm.startBroadcast(pk);

        nftManager.approve(LIQUIDITY_ORCHESTRATOR, tokenId);

        UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory withdrawInput = _buildWithdrawInput(uniId, positionId, broadcaster);
        uint256 amountOut = LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).withdrawLiquidityAndCollectFees(withdrawInput);

        console.log("withdrawLiquidityAndCollectFees OK. USDC out:", amountOut);
    }

    /// @param broadcaster Owner del NFT (debe coincidir con la wallet que ejecuta)
    function _withdrawOnly(address broadcaster) internal {
        INonfungiblePositionManager nftManager = INonfungiblePositionManager(AddressProvider(ADDRESS_PROVIDER).getAddress("UniswapNFTPositionManager"));

        // POSITION_ID y UNI_ID desde env (ej. tras provide) o defaults
        uint256 positionId = vm.envOr("POSITION_ID", uint256(1));
        uint128 uniId = uint128(vm.envOr("UNI_ID", uint256(5378005)));

        nftManager.approve(LIQUIDITY_ORCHESTRATOR, uniId);

        UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory withdrawInput = _buildWithdrawInput(uniId, positionId, broadcaster);
        uint256 amountOut = LiquidityOrchestrator(LIQUIDITY_ORCHESTRATOR).withdrawLiquidityAndCollectFees(withdrawInput);

        console.log("withdrawLiquidityAndCollectFees OK. USDC out:", amountOut);
    }

    /// @dev Params frontend: WBTC->USDC (fee 3000), WETH->USDC (fee 100)
    function _buildWithdrawInputFromFrontend(uint128 uniId, uint256 positionId, address user) internal pure returns (UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory) {
        UniswapLib.SwapInstruction[] memory inst0 = new UniswapLib.SwapInstruction[](1);
        inst0[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: WBTC,
            tokenOut: USDC,
            amountIn: 0,
            amountOut: 0,
            poolOrPair: 0x599bB1269B71625dA7761ba79A228230c8354C55,
            fee: 500,
            poolKey: _emptyPoolKey()
        });

        UniswapLib.SwapInstruction[] memory inst1 = new UniswapLib.SwapInstruction[](1);
        inst1[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: WETH,
            tokenOut: USDC,
            amountIn: 0,
            amountOut: 0,
            poolOrPair: 0x6f38e884725a116C9C7fBF208e79FE8828a2595F,
            fee: 100,
            poolKey: _emptyPoolKey()
        });

        UniswapLib.SwapInput memory swapInput0 = UniswapLib.SwapInput({
            tokenIn: WBTC,
            tokenOut: USDC,
            swapInstructions: inst0,
            amountIn0: 0,
            to: address(0)
        });
        UniswapLib.SwapInput memory swapInput1 = UniswapLib.SwapInput({
            tokenIn: WETH,
            tokenOut: USDC,
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

    function _buildInput() internal view returns (UniswapLib.ExecuteProvideLiquidityInput memory) {
        UniswapLib.SwapInstruction[] memory inst0 = new UniswapLib.SwapInstruction[](1);
        inst0[0] = UniswapLib.SwapInstruction({
            protocol: UniswapLib.Protocol.UniswapV3,
            tokenIn: USDC,
            tokenOut: WETH,
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
            tokenOut: WETH,
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
            token1: WETH,
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

    /// @dev Para provide+withdraw: posicion WBTC/WETH -> swaps WBTC->USDC, WETH->USDC (params frontend)
    function _buildWithdrawInput(uint128 uniId, uint256 positionId, address user) internal pure returns (UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory) {
        return _buildWithdrawInputFromFrontend(uniId, positionId, user);
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
