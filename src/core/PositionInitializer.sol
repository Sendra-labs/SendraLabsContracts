//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SendraStorage } from "./SendraStorage.sol";
import { SendraLib } from "../lib/Sendra.lib.sol";
import { Roles } from "../security/Roles.sol";
import { AddressProvider } from "./config/AddressProvider.sol";

/**
 * @title PositionInitializer
 * @notice Opens a position in SendraStorage. Markets and SendraLP both call this.
 * @dev Only a contract already accepted by Roles can open a position.
 */
contract PositionInitializer {

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    modifier onlyProtocol() {
        if (!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType, address _user) external onlyProtocol {
        SendraStorage sendraStorage = SendraStorage(addressProvider.getAddress("SendraStorage"));
        sendraStorage.updateUserTransactionCount(_user, 1);
        uint256 positionId = sendraStorage.getUser(_user).totalPositions + 1;
        sendraStorage.addPositionToUser(_user, SendraLib.Position(_positionType, positionId, 0, true, _newPositionData));
    }

    error SenderNotAllowed();
}
