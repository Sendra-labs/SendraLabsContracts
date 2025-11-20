//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract GasPrice {
    function testGasPrice() public view returns (uint256 gasPriceWei, uint256 gasPriceGwei) {
    gasPriceWei = tx.gasprice;
    gasPriceGwei = tx.gasprice / 1e9;
    return (gasPriceWei, gasPriceGwei);
}
}