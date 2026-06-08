//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { UniswapLib } from "./Uniswap.lib.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";

library UniswapParamsEncoderLib {

    error UnsupportedProtocol();

    /// @notice Build UniversalRouter (commands, inputs) from a SwapInput.
    /// @dev V3 hops that form a coherent chain (out of hop N == in of hop N+1) are
    ///      packed into a single V3_SWAP_EXACT_IN command with a long path. The
    ///      UniversalRouter chains the swaps internally using actual on-chain
    ///      outputs, so callers do not need to predict intermediate amounts at the
    ///      wei level. V2 and V4 hops are still emitted as one command per hop.
    ///      Multiple V3 chains in the same SwapInput (split routes) are emitted as
    ///      independent commands.
    function createParams(UniswapLib.SwapInput memory params, address intermediateRecipient)
        internal
        pure
        returns (bytes memory, bytes[] memory)
    {
        bytes memory commandsBuf = new bytes(params.swapInstructions.length);
        bytes[] memory inputsBuf = new bytes[](params.swapInstructions.length);
        uint256 outCount = 0;

        uint256 i = 0;
        while (i < params.swapInstructions.length) {
            UniswapLib.SwapInstruction memory hop = params.swapInstructions[i];

            if (hop.protocol == UniswapLib.Protocol.UniswapV3) {
                uint256 j = i;
                while (
                    j + 1 < params.swapInstructions.length &&
                    params.swapInstructions[j + 1].protocol == UniswapLib.Protocol.UniswapV3 &&
                    params.swapInstructions[j].tokenOut == params.swapInstructions[j + 1].tokenIn
                ) {
                    j++;
                }

                UniswapLib.SwapInstruction memory firstHop = params.swapInstructions[i];
                UniswapLib.SwapInstruction memory lastHop = params.swapInstructions[j];

                address recipient = lastHop.tokenOut == params.tokenOut
                    ? params.to
                    : intermediateRecipient;

                bool payerIsUser = firstHop.tokenIn == params.tokenIn;

                bytes memory path = abi.encodePacked(firstHop.tokenIn, firstHop.fee, firstHop.tokenOut);
                for (uint256 k = i + 1; k <= j; k++) {
                    UniswapLib.SwapInstruction memory step = params.swapInstructions[k];
                    path = abi.encodePacked(path, step.fee, step.tokenOut);
                }

                commandsBuf[outCount] = bytes1(0x00); // V3_SWAP_EXACT_IN
                inputsBuf[outCount] = abi.encode(
                    recipient,
                    firstHop.amountIn,
                    lastHop.amountOut,
                    path,
                    payerIsUser
                );
                outCount++;
                i = j + 1;
                continue;
            }

            address hopRecipient = hop.tokenOut == params.tokenOut
                ? params.to
                : intermediateRecipient;
            bool hopPayerIsUser = hop.tokenIn == params.tokenIn;

            if (hop.protocol == UniswapLib.Protocol.UniswapV2) {
                commandsBuf[outCount] = bytes1(0x08);
                inputsBuf[outCount] = abi.encode(
                    hopRecipient,
                    hop.amountIn,
                    hop.amountOut,
                    [hop.tokenIn, hop.tokenOut],
                    hopPayerIsUser
                );
            } else if (hop.protocol == UniswapLib.Protocol.UniswapV4) {
                commandsBuf[outCount] = bytes1(0x10);
                bytes memory actions = abi.encodePacked(bytes1(0x06), bytes1(0x0c), bytes1(0x0f));
                bytes[] memory v4Params = new bytes[](3);
                bool zeroForOne = hop.tokenIn == address(uint160(Currency.unwrap(hop.poolKey.currency0)));
                v4Params[0] = abi.encode(
                    hop.poolKey,
                    zeroForOne,
                    uint128(hop.amountIn),
                    uint128(hop.amountOut),
                    uint256(0),
                    bytes("")
                );
                v4Params[1] = abi.encode(Currency.wrap(hop.tokenIn), hop.amountIn);
                v4Params[2] = abi.encode(Currency.wrap(hop.tokenOut), hop.amountOut);
                inputsBuf[outCount] = abi.encode(actions, v4Params);
            } else {
                revert UnsupportedProtocol();
            }
            outCount++;
            i++;
        }

        bytes memory commands = new bytes(outCount);
        bytes[] memory inputs = new bytes[](outCount);
        for (uint256 k = 0; k < outCount; k++) {
            commands[k] = commandsBuf[k];
            inputs[k] = inputsBuf[k];
        }
        return (commands, inputs);
    }
}
