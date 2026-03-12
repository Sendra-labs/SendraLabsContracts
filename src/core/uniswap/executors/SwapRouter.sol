//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";

contract SwapRouter is ReentrancyGuard {

    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    function executeSwap(UniswapLib.SwapInput memory _input) public {

    }
}