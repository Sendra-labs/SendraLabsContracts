//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";

library UniswapLib {

    enum Protocol {
        UniswapV2,
        UniswapV3,
        UniswapV4
    }

    struct SwapInstruction {
        Protocol protocol;
        address tokenIn; // initial token in the swap
        address tokenOut; // final token in the swap
        uint256 amountIn; // amount for the initial token
        uint256 amountOut; // amount for the final token (amountOutMin)
        address poolOrPair; // v2 or v3
        uint24 fee; // v3
        PoolKey poolKey; // v4
        
    }

    struct SwapInput {
        address tokenIn; // initial token
        address tokenOut; // final token (amountOutMin)
        SwapInstruction[] swapInstructions;
        uint256 amountIn0; // initial amount
        address to; // recipient
    }

    struct ProvideLiquidityInput {
        Protocol protocol;
        address token0; 
        address token1;
        address recipient;
        address user;
        uint256 amount0; 
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
    }

    struct ExecuteProvideLiquidityInput {
        SwapInput swapInput0; 
        SwapInput swapInput1;
        ProvideLiquidityInput provideLiquidityInput;
        bool isSendraRecipient;
    }

    struct CollectParams {
        uint128 uniId;
        uint256 positionId; // Sendra
        bool isWithdraw; // is just (false) collecting fees or is (true) withdrawing liquidity + fees
        address user;
    }

    struct WithdrawLiquidityInput {
        uint128 uniId;
        uint256 positionId; // Sendra
        address user;
    }

    struct ExecuteWithdrawLiquidityAndCollectFees {
        WithdrawLiquidityInput withdrawLiquidityInput;
        SwapInput swapInput0;
        SwapInput swapInput1;
    }

    struct ExecuteCollectFeesOnly {
        CollectParams collectParams;
        SwapInput swapInput0;
        SwapInput swapInput1;
    }
}