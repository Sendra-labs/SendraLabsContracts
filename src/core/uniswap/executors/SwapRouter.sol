//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { UniversalRouter } from "@uniswap/universal-router/UniversalRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UniswapParamsEncoderLib } from "../../../lib/uniswap/ParamsEncoder.lib.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract SwapRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    UniversalRouter public immutable universalRouter;
    IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor(address universalRouterAddress) {
        universalRouter = UniversalRouter(payable(universalRouterAddress));
    }

    function atomicSwap(UniswapLib.SwapInput calldata _input1, UniswapLib.SwapInput calldata _input2) public {
        executeSwap(_input1);
        executeSwap(_input2);
    }

    function executeSwap(UniswapLib.SwapInput calldata _input) public {
        IERC20 tokenIn = IERC20(_input.tokenIn);
        uint256 have = tokenIn.balanceOf(address(this));
        if (have < _input.amountIn0) revert InsufficientTokenInBalance(_input.tokenIn, have, _input.amountIn0);

        tokenIn.forceApprove(address(PERMIT2), _input.amountIn0);
        PERMIT2.approve(_input.tokenIn, address(universalRouter), uint160(_input.amountIn0), type(uint48).max);
        (bytes memory commands, bytes[] memory inputs) = UniswapParamsEncoderLib.createParams(_input, address(universalRouter));
        universalRouter.execute(commands, inputs);
    }

    error InsufficientTokenInBalance(address tokenIn, uint256 balance, uint256 required);

}