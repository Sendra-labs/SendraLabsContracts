//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MainReader } from "../src/core/MainReader.sol";
import { MarketNeutralStorage } from "../src/core/bundles/storage/MarketNeutralStorage.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { MarketNeutralLib } from "../src/lib/MarketNeutral/MarketNeutralLib.sol";

contract RegFromCallback {
    AddressProvider public addressProvider;
    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }
    function regFromCallback() public {
        MarketNeutralStorage marketNeutralStorage = MarketNeutralStorage(addressProvider.getAddress("MarketNeutralStorage"));
        MarketNeutralLib.RawExecutionData memory executionData = MarketNeutralLib.RawExecutionData({
            positionId: 1,
            receiver: 0x8DE959Dc78ed8948851af6a5453c01fD8AEDA8E0,
            outputToken: 0x8DE959Dc78ed8948851af6a5453c01fD8AEDA8E0,
            outputAmount: 123456,
            pnl: 100000,
            executionPrice: 909090,
            collateralTokenPrice: 65432,
            isLongSide: false, 
            processed: false,
            timestamp: block.timestamp
        });
        marketNeutralStorage.storeRawExecutionData(0x6d5f7ffadce6f5623998e9cca880960e17c5fa1904146392e188962aa9d38f03, executionData);
    }
}