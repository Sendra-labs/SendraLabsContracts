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

    error SenderNotAllowed();

    function initializePosition(bytes[] memory _newPositionData, uint128 _positionType, address _user) external onlyProtocol {
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        
        protocolStorage.updateUserTransactionCount(_user, 1);
        ProtocolLib.GlobalPosition memory userGlobalPosition = protocolStorage.getUser(_user).globalPosition;
        
        uint256 positionId = userGlobalPosition.totalPositions + 1;

        protocolStorage.updateUserGlobalPosition(
            _user, 
            ProtocolLib.GlobalPosition(
                positionId, // == totalPositions + 1
                userGlobalPosition.activePositions + 1,
                createPositions(userGlobalPosition.positions, _newPositionData, _positionType, positionId)
            )
        );
    }

    function createPositions(
        ProtocolLib.Position[] memory _positions, 
        bytes[] memory _newPositionData, 
        uint128 _positionType,
        uint256 _positionId
    ) internal pure returns (
        ProtocolLib.Position[] memory
    ) {

        ProtocolLib.Position[] memory newPositions = new ProtocolLib.Position[](_positions.length + 1);
        
        ProtocolLib.Position memory newPosition = ProtocolLib.Position(_positionType, _positionId, 0, true, _newPositionData);
        
        for(uint256 i = 0; i < _positions.length; i++) {
            newPositions[i] = _positions[i];
        }
        
        newPositions[newPositions.length - 1] = newPosition;

        return newPositions;
    }


}