//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../config/AddressProvider.sol";
import { HoldingsStorage } from "../storage/HoldingsStorage.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { HoldingsPositionManager } from "../executors/HoldingsPositionManager.sol";
import { SecureAccount } from "./SecureAccount.sol";

contract AccountFactory {

    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
    }

    function deployAccount(address _user) public {
        HoldingsStorage holdingsStorage = HoldingsStorage(addressProvider.getAddress("HoldingsStorage"));
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        uint256 positionId = protocolStorage.getUser(_user).totalPositions + 1;
        holdingsStorage.registerAccount(_user, address(new SecureAccount(_user, address(addressProvider))), positionId);
        bytes[] memory emptyPositionStructure = new bytes[](8);
        emptyPositionStructure[0] = abi.encode(uint256(0)); // Total USDC spent/invested in BTC
        emptyPositionStructure[1] = abi.encode(uint256(0)); // Total USDC earned/recovered from BTC
        emptyPositionStructure[2] = abi.encode(uint256(0)); // Total BTC bought
        emptyPositionStructure[3] = abi.encode(uint256(0)); // Average purchase price of BTC
        emptyPositionStructure[4] = abi.encode(uint256(0)); // Average sale price of BTC
        emptyPositionStructure[5] = abi.encode(uint256(0)); // Last purchase price of BTC
        emptyPositionStructure[6] = abi.encode(uint256(0)); // Last sale price of BTC
        emptyPositionStructure[7] = abi.encode(uint256(0)); // Total BTC sold
        HoldingsPositionManager(addressProvider.getAddress("HoldingsPositionManager")).initializeHoldingPosition(protocolStorage, emptyPositionStructure, 1000000, _user);
    }
}