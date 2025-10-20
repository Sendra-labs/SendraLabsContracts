//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseOrderUtils } from "../../lib/GMX lib/BaseOrdersUtils.sol";

interface IExchangeRouter {
    function createOrder(BaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external payable;
    function multicall(bytes[] calldata data) external payable;
}