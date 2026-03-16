//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { LiquidityManager } from "./LiquidityManager.sol";
import { SwapRouter } from "./SwapRouter.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityOrchestrator {

    LiquidityManager public immutable liquidityManager;
    SwapRouter public immutable swapRouter;

    constructor(address _liquidityManager, address _swapRouter) {
        liquidityManager = LiquidityManager(_liquidityManager);
        swapRouter = SwapRouter(_swapRouter);
    }

    function ProvideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata _input) public {
        UniswapLib.SwapInput memory swapInput0 = _input.swapInput0;
        UniswapLib.SwapInput memory swapInput1 = _input.swapInput1;
        UniswapLib.ProvideLiquidityInput memory provideLiquidityInput = _input.provideLiquidityInput;
        
        if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV3){
            
            IERC20(swapInput0.tokenIn).transferFrom(msg.sender, address(swapRouter), swapInput0.amountIn0);
            IERC20(swapInput1.tokenIn).transferFrom(msg.sender, address(swapRouter), swapInput1.amountIn0);
            
            swapInput0.to = address(liquidityManager);
            swapInput1.to = address(liquidityManager);

            swapRouter.atomicSwap(swapInput0, swapInput1);

            provideLiquidityInput.recipient = _input.isSendraRecipient ? address(this) : msg.sender;

            liquidityManager.addLiquidityV3(provideLiquidityInput);

        } else if(_input.protocol == UniswapLib.Protocol.UniswapV4){
            //TODO: Implement UniswapV4
        }
    }
}