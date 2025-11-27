//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";

contract ProxyAccessControl {
    Roles public roles;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    mapping(address => bool) public isProxy;

    function setIsProtocolProxy(address _contract) public onlyProtocol {
        isProxy[_contract] = true;
    }

    function isProtocolProxy(address _contract) public view returns (bool) {
        return isProxy[_contract];
    }

    error SenderNotAllowed();
}