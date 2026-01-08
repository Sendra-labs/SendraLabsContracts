//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { PricesLib } from "../../src/lib/Prices.lib.sol";
import { AddressProvider } from "../../src/core/config/AddressProvider.sol";
import { GMXPrices } from "../../src/periphery/utilsGMX/GMXPrices.sol";

contract Prices is Script {

    AddressProvider public immutable addressProvider = AddressProvider(0x73836d093005Dafeb3446c6DB10f325a52ea6f0E);
    GMXPrices public immutable gmxPrices = GMXPrices(addressProvider.getAddress("GMXPrices"));


    function run() public view {
        console.log("GMXPrices: ", address(gmxPrices));
        console.log("Price of BNB/USDC: ", gmxPrices.getPrice(0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B));
        console.log("Price of TIA/USDC: ", gmxPrices.getPrice(0xBeB1f4EBC9af627Ca1E5a75981CE1AE97eFeDA22));
        (
            uint256 indexPriceBNB,
            uint256 longPriceBNB,
            uint256 shortPriceBNB
        ) = gmxPrices.getMarketPrices(0x2d340912Aa47e33c90Efb078e69E70EFe2B34b9B);
        console.log("BNB - Price of index: ", indexPriceBNB);
        console.log("BNB - Price of LONG: ", longPriceBNB);
        console.log("BNB - Price of SHORT: ", shortPriceBNB);
        (
            uint256 indexPriceTIA,
            uint256 longPriceTIA,
            uint256 shortPriceTIA
        ) = gmxPrices.getMarketPrices(0xBeB1f4EBC9af627Ca1E5a75981CE1AE97eFeDA22);
        console.log("TIA - Price of index: ", indexPriceTIA);
        console.log("TIA - Price of LONG: ", longPriceTIA);
        console.log("TIA - Price of SHORT: ", shortPriceTIA);
    }
    // command to run the script:
    // forge script script/readData/prices.sol:Prices --rpc-url https://1rpc.io/arb -vvvv
}