//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

library UniswapLib {

    enum Protocol {
        UniswapV2,
        UniswapV3,
        UniswapV4
    }

    struct SwapInstruction {
        Protocol protocol;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        address poolOrPair; // v2 or v3
        uint24 fee; // v3
        PoolKey poolKey; // v4
        
    }

    struct SwapInput {
        address tokenIn;
        address tokenOut;
        SwapInstruction[] swapInstructions;
        uint256 amountIn0;
        address to;
    }

}