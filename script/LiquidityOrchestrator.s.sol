// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityManager } from "../src/core/uniswap/executors/LiquidityManager.sol";
import { LiquidityOrchestrator } from "../src/core/uniswap/executors/LiquidityOrchestrator.sol";
import { SwapRouter } from "../src/core/uniswap/executors/SwapRouter.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { Roles } from "../src/security/Roles.sol";
import { UniswapLib } from "../src/lib/uniswap/Uniswap.lib.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Script: deploy LiquidityOrchestrator + provideLiquidity (USDC -> 2 swaps -> WBTC/WETH pool)
 *
 * COMANDOS:
 *   # Deploy + provideLiquidity
 *   RUN_PROVIDE_LIQUIDITY=1 forge script script/LiquidityOrchestrator.s.sol --broadcast --rpc-url arbitrum
 *
 *   # Solo deploy
 *   forge script script/LiquidityOrchestrator.s.sol --broadcast --rpc-url arbitrum
 *
 *   # Solo provideLiquidity (Orchestrator ya desplegado)
 *   LIQUIDITY_ORCHESTRATOR=0x... RUN_PROVIDE_LIQUIDITY=1 forge script script/LiquidityOrchestrator.s.sol --broadcast --rpc-url arbitrum
 *
 * Env vars:
 *   ADMIN1_PRIVATE_KEY o PRIVATE_KEY  - Clave privada (admin para setAddress en AddressProvider)
 *   RUN_PROVIDE_LIQUIDITY = "1"        - Ejecutar provideLiquidity después del deploy
 *   LIQUIDITY_ORCHESTRATOR             - Si existe, solo ejecuta provideLiquidity (no despliega)
 *
 * Params modificables abajo:
 */
contract LiquidityOrchestratorScript is Script {

    address constant ADDRESS_PROVIDER = 0x73836d093005Dafeb3446c6DB10f325a52ea6f0E;
    address constant UNIVERSAL_ROUTER = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant NFT_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // --- Params modificables ---
    uint256 AMOUNT_USDC_SWAP0 = 50_000;  // 0.05 USDC (6 decimals)
    uint256 AMOUNT_USDC_SWAP1 = 50_000;  // 0.05 USDC (6 decimals)
    uint256 AMOUNT_OUT_MIN0 = 0;
    uint256 AMOUNT_OUT_MIN1 = 0;
    uint24 FEE_TIER_SWAP = 500;          // 0.05% para swap USDC->WETH/WBTC
    // Pool WBTC/WETH (token0 < token1)
    uint24 POOL_FEE = 3000;              // 0.3%
    int24 TICK_LOWER = -887220;          // full range (múltiplo de 60)
    int24 TICK_UPPER = 887220;
    bool IS_SENDRA_RECIPIENT = false;     // true = NFT al orchestrator, false = al msg.sender

    function setUp() public {}

    function _getPrivateKey() internal view returns (uint256) {
        try vm.envUint("ADMIN1_PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        try vm.envUint("PRIVATE_KEY") returns (uint256 v) { return v; } catch {}
        revert("ADMIN1_PRIVATE_KEY o PRIVATE_KEY required en .env");
    }

    function run() public {
        uint256 pk = _getPrivateKey();
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        address orchestratorAddr = vm.envOr("LIQUIDITY_ORCHESTRATOR", address(0));

        if (orchestratorAddr == address(0)) {
            orchestratorAddr = _deployAll(deployer);
        }

        if (vm.envOr("RUN_PROVIDE_LIQUIDITY", uint256(0)) == 1) {
            _provideLiquidity(orchestratorAddr, deployer);
        }

        vm.stopBroadcast();
    }

    function _deployAll(address) internal returns (address orchestratorAddr) {
        AddressProvider ap = AddressProvider(ADDRESS_PROVIDER);
        ap.setAddress("UniswapNFTPositionManager", NFT_POSITION_MANAGER);
        ap.setAddress("UniswapV3Factory", FACTORY);

        LiquidityManager liquidityManager = new LiquidityManager(ADDRESS_PROVIDER);
        console.log("LiquidityManager desplegado:", address(liquidityManager));

        SwapRouter swapRouter = new SwapRouter(UNIVERSAL_ROUTER);
        console.log("SwapRouter desplegado:", address(swapRouter));

        Roles roles = Roles(ap.getAddress("Roles"));
        roles.allowContract(address(liquidityManager), "LiquidityManager");
        ap.setAddress("LiquidityManager", address(liquidityManager));
        ap.setAddress("SwapRouter", address(swapRouter));
        LiquidityOrchestrator orchestrator = new LiquidityOrchestrator(ADDRESS_PROVIDER);
        orchestratorAddr = address(orchestrator);
        console.log("LiquidityOrchestrator desplegado:", orchestratorAddr);

        ap.setAddress("LiquidityOrchestrator", orchestratorAddr);

        return orchestratorAddr;
    }

    function _provideLiquidity(address orchestratorAddr, address recipient) internal {
        uint256 totalUsdc = AMOUNT_USDC_SWAP0 + AMOUNT_USDC_SWAP1;
        IERC20(USDC).approve(orchestratorAddr, totalUsdc);

        UniswapLib.ExecuteProvideLiquidityInput memory input = _buildInput(recipient);
        LiquidityOrchestrator(orchestratorAddr).provideLiquidity(input);

        console.log("provideLiquidity ejecutado. Recipient:", recipient);
    }

    function _buildInput(address recipient) internal view returns (UniswapLib.ExecuteProvideLiquidityInput memory) {
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

        // amount0/amount1: máximos para mint (usar valores altos, el PM usa lo disponible)
        UniswapLib.ProvideLiquidityInput memory liqInput = UniswapLib.ProvideLiquidityInput({
            protocol: UniswapLib.Protocol.UniswapV3,
            token0: WBTC,
            token1: WETH,
            recipient: recipient,
            user: recipient,
            amount0: 60,
            amount1: 19157338949957,
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

/*
Ejecutar desde la raíz del proyecto (carpeta protocol, no src):

cd /path/to/protocol

# Deploy completo
forge script script/LiquidityOrchestrator.s.sol:LiquidityOrchestratorScript --broadcast --rpc-url arbitrum

# Solo provideLiquidity (orchestrator ya desplegado)
LIQUIDITY_ORCHESTRATOR=0xc9085c56D807bBfd6FA7d82e74a19EE9572b2b55 RUN_PROVIDE_LIQUIDITY=1 forge script script/LiquidityOrchestrator.s.sol:LiquidityOrchestratorScript --broadcast --rpc-url arbitrum

# Deploy + provideLiquidity
RUN_PROVIDE_LIQUIDITY=1 forge script script/LiquidityOrchestrator.s.sol:LiquidityOrchestratorScript --broadcast --rpc-url arbitrum

Env: ADMIN1_PRIVATE_KEY o PRIVATE_KEY en .env

LiquidityManager desplegado: 0xc90B30327cE029a100DD5816f1299303C7FC11Bf
  SwapRouter desplegado: 0x9D51C11195BD2A398D91508C5BEffe8A979FC6a7
  LiquidityOrchestrator desplegado: 0xc9085c56D807bBfd6FA7d82e74a19EE9572b2b55
*/