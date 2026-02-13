//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../config/AddressProvider.sol";
import { Roles } from "../../../security/Roles.sol";

contract HoldingsStorage {

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    mapping(address => address) public userAccount;
    mapping(address => uint256) public userPositionId;

    function registerAccount(address _user, address _account, uint256 _positionId) public onlyProtocol {
        if(userAccount[_user] != address(0)) revert AccountAlreadyRegistered();
        userAccount[_user] = _account;
        userPositionId[_user] = _positionId;
    }

    function getAccount(address _user) public view returns (address) {
        return userAccount[_user];
    }

    function getPositionId(address _user) public view returns (uint256) {
        return userPositionId[_user];
    }

    error AccountAlreadyRegistered();
    error SenderNotAllowed();
}