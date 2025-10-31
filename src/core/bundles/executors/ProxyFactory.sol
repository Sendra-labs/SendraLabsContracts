//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MarketNeutralProxy } from "./proxy.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";

contract ProxyFactory {

    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    function deploy(uint256 _id) external returns (address){
        address manager = addressProvider.getAddress("ProxyManager");
        if(msg.sender != address(manager)) revert SenderNotAllowed();
        MarketNeutralProxy proxy = new MarketNeutralProxy(address(addressProvider), _id);
        return address(proxy);
    }

    error SenderNotAllowed();
}