//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";

contract SendraToken is ERC20 {

    Roles public immutable roles;
    AddressProvider public immutable addressProvider;
    uint8 private _decimals;
    string private _name;
    string private _symbol;
    
    constructor(address _addressProvider, uint8 tokenDecimals, string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
        _decimals = tokenDecimals;
        _name = tokenName;
        _symbol = tokenSymbol;
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address _to, uint256 _amount) public onlyProtocol {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyProtocol {
        _burn(_from, _amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transferSendraBtc(address _to, uint256 _amount) public onlyProtocol returns (bool) {
        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFromSendraBtc(address _from, address _to, uint256 _amount) public onlyProtocol returns (bool) {
        _transfer(_from, _to, _amount);
        return true;
    }

    function approveSendraBtc(address _spender, uint256 _amount) public onlyProtocol returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert ApprovesNotAllowed();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersNotAllowed();
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersNotAllowed();
    }

    error SenderNotAllowed();
    error TransfersNotAllowed();
    error ApprovesNotAllowed();

}