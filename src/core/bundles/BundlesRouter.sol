//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../security/Roles.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BundlesRouter is ReentrancyGuard {
    Roles public immutable roles;
    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function route(address _bundle, uint8 functionId, bytes[] calldata _data, uint256[] calldata _types) public onlyProtocol nonReentrant {
        (bool success,) = _bundle.call(
            abi.encodeWithSelector(
                bytes4(
                    keccak256("execute(uint8,bytes[],uint256[])")
                ), 
                functionId,
                _data, 
                _types
            )
        );
        if(!success) revert ExecutionFailed();
    }


    error SenderNotAllowed();
    error ExecutionFailed();
}