//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract LiquidityManager {


    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1) public {}

    function removeLiquidity(address token0, address token1, uint256 liquidity) public returns (uint256 amount0, uint256 amount1) {}

    function collectFees(address token0, address token1) public returns (uint256 amount0, uint256 amount1) {}

    
}