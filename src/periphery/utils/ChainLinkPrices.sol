//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PricesLib } from "../../lib/Prices.lib.sol";
import { AddressProvider } from "../../core/config/AddressProvider.sol";
import { Roles } from "../../security/Roles.sol";

contract ChainLinkPrices {
    using PricesLib for address;

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    mapping(address => address) public priceFeeds;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
        priceFeeds[0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f] = 0x6ce185860a4963106506C203335A2910413708e9;
    }

    modifier onlyAdmin() {
        if (!roles.checkAdmin(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function addPriceFeed(address _token, address _priceFeed) external onlyAdmin {
        priceFeeds[_token] = _priceFeed;
    }

    function getPrice(address _token) public view returns (uint256) {
        return priceFeeds[_token].getPriceFromFeed();
    }

    error SenderNotAllowed();
}
