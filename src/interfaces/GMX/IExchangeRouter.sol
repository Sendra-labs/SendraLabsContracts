//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IBaseOrderUtils } from "gmx-synthetics/order/IBaseOrderUtils.sol";

interface IExchangeRouter {
    function createOrder(IBaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external payable;
    function multicall(bytes[] calldata data) external payable;
}