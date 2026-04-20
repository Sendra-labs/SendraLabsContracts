//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { UniswapLib } from "./Uniswap.lib.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";

library UniswapParamsEncoderLib {

    function createParams(UniswapLib.SwapInput memory params, address intermediateRecipient) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory commands = new bytes(params.swapInstructions.length);
        for(uint8 i = 0; i < params.swapInstructions.length; i++){
            if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV2){
                commands[i] = bytes1(0x08);
            } else if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV3){
                commands[i] = bytes1(0x00);
            } else if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV4){
                commands[i] = bytes1(0x10);
            }
        }

        bytes[] memory inputs = new bytes[](params.swapInstructions.length);

        for(uint8 i = 0; i < params.swapInstructions.length; i++){
            
            address recipient = params.swapInstructions[i].tokenOut == params.tokenOut
                ? params.to
                : intermediateRecipient;

            if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV2){
                inputs[i] = abi.encode(
                    recipient,
                    params.swapInstructions[i].amountIn,
                    params.swapInstructions[i].amountOut,
                    [params.swapInstructions[i].tokenIn, params.swapInstructions[i].tokenOut],
                    true
                );
            } else if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV3){
                inputs[i] = abi.encode(
                    recipient,
                    params.swapInstructions[i].amountIn,
                    params.swapInstructions[i].amountOut,
                    abi.encodePacked(params.swapInstructions[i].tokenIn, params.swapInstructions[i].fee, params.swapInstructions[i].tokenOut),
                    true
                );
            } else if(params.swapInstructions[i].protocol == UniswapLib.Protocol.UniswapV4){
                // V4: SWAP_EXACT_IN_SINGLE (0x06), SETTLE_ALL (0x0c), TAKE_ALL (0x0f)
                bytes memory actions = abi.encodePacked(bytes1(0x06), bytes1(0x0c), bytes1(0x0f));
                bytes[] memory v4Params = new bytes[](3);
                bool zeroForOne = params.swapInstructions[i].tokenIn == address(uint160(Currency.unwrap(params.swapInstructions[i].poolKey.currency0)));
                v4Params[0] = abi.encode(
                    params.swapInstructions[i].poolKey,
                    zeroForOne,
                    uint128(params.swapInstructions[i].amountIn),
                    uint128(params.swapInstructions[i].amountOut),
                    uint256(0),
                    bytes("")
                );
                // params[1]: SETTLE_ALL (Currency currency, uint256 maxAmount)
                v4Params[1] = abi.encode(
                    Currency.wrap(params.swapInstructions[i].tokenIn),
                    params.swapInstructions[i].amountIn
                );
                // params[2]: TAKE_ALL (Currency currency, uint256 minAmount)
                v4Params[2] = abi.encode(
                    Currency.wrap(params.swapInstructions[i].tokenOut),
                    params.swapInstructions[i].amountOut
                );
                inputs[i] = abi.encode(actions, v4Params);
            }
        }
        return(commands, inputs);
    }

}