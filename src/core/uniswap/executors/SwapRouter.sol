//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { UniversalRouter } from "@uniswap/universal-router/UniversalRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UniswapParamsEncoderLib } from "../../../lib/uniswap/ParamsEncoder.lib.sol";

contract SwapRouter is ReentrancyGuard {

    AddressProvider public immutable addressProvider;
    UniversalRouter public immutable universalRouter;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        universalRouter = UniversalRouter(addressProvider.getAddress("UniversalRouter"));
    }

    function atomicSwap(UniswapLib.SwapInput calldata _input1, UniswapLib.SwapInput calldata _input2) public {
        executeSwap(_input1);
        executeSwap(_input2);
    }

    function executeSwap(UniswapLib.SwapInput calldata _input) public {
        IERC20(_input.tokenIn).approve(universalRouter, _input.amountIn0);
        (bytes memory commands, bytes[] memory inputs) = UniswapParamsEncoderLib.createParams(_input, address(this));
        UniversalRouter(universalRouter).execute(commands, inputs);
    }

}