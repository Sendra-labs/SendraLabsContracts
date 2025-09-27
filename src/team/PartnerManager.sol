//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ProtocolLib} from "../lib/Protocol.lib.sol";
import { Roles } from "../security/Roles.sol";

contract PartnerManager is ReentrancyGuard {

    constructor(ProtocolLib.Partner memory _partner, address _roles) {
        roles = Roles(_roles);
        partner = _partner;
    }

    /**
     * @notice Modifier that restricts access to authorized protocol contracts only
     * @dev Uses Roles contract to verify that caller is a registered protocol contract
     */
    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    ProtocolLib.Partner internal partner;
    Roles public immutable roles;

    error SenderNotAllowed();
}