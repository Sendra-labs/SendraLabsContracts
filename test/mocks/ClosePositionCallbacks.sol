//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EventUtils} from "gmx-synthetics/event/EventUtils.sol";
import {ProxyManager} from "../../../src/core/bundles/storage/ProxyManager.sol";
import {AddressProvider} from "../../../src/core/config/AddressProvider.sol";

contract ClosePositionCallbacksMock {

    AddressProvider public addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }
    
    function afterOrderExecution(uint256 proxyId) public {
        ProxyManager proxyManager = ProxyManager(addressProvider.getAddress("ProxyManager"));
        proxyManager.setAvailable(proxyId);
    }
}