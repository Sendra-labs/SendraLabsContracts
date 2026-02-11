/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒        UNISWAP EXECUTOR                                                                                                                                   
________________________________________________________________
*/


//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import { AddressProvider } from "../../utils/AddressProvider.sol";
import { PoolRegistry } from "../config/PoolRegistry.sol";

contract UniExecutor is ReentrancyGuard {

    ISwapRouter public swapRouter;
    IERC20 public usdc;

    constructor(address _addressProvider) {
        address swapRouter = AddressProvider(_addressProvider).getAddress("SwapRouter");
        address usdc = AddressProvider(_addressProvider).getAddress("USDC");
        swapRouter = ISwapRouter(swapRouter);
        usdc = IERC20(usdc);
    }


    function swap(bool isBuy, uint256 _amountIn, address _token) public nonReentrant returns(uint256 _amountOut) {
        IERC20(_token).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_token).approve(address(swapRouter), _amountIn);
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: isBuy ? getSwapData(_token).buyPath : getSwapData(_token).sellPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0
            });

        _amountOut = swapRouter.exactInput(params);
        return _amountOut;
    }

    function getPoolFee(address poolToSwap) public view returns(uint24){
        IUniswapV3PoolState pool = IUniswapV3PoolState(poolToSwap);
        uint24 fee = pool.fee();
        return fee;
    } 

    function getPoolPrice(address poolToSwap) public view returns(uint160){
        IUniswapV3PoolState pool = IUniswapV3PoolState(poolToSwap);
        (uint160 priceSqrt, , , , , , ) = pool.slot0();
        return priceSqrt;
    }

    function getPool(address _token) public view returns(address){
        return poolRegistry.getPool(_token);
    }

}