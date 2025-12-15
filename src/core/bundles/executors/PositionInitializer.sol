//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { ProxyAccessControl } from "../security/proxyAccessControl.sol";

contract PositionInitializer {

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    modifier onlyProtocol() {
        if(
            !roles.isProtocolContract(msg.sender)
            && !ProxyAccessControl(addressProvider.getAddress("ProxyAccessControl")).isProtocolProxy(msg.sender)
        ) 
        revert SenderNotAllowed();
        _;
    }

    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType, address _user) external onlyProtocol {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        protocolStorage.updateUserTransactionCount(_user, 1);        
        uint256 positionId = protocolStorage.getUser(_user).totalPositions + 1;
        protocolStorage.addPositionToUser(_user, ProtocolLib.Position(_positionType, positionId, 0, true, _newPositionData));
    }

    error SenderNotAllowed();

}