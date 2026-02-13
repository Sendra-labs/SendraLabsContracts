//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { UniExecutor } from "../executors/UniExecutor.sol";

contract SecureAccount is Ownable {

    AddressProvider public immutable addressProvider;

    constructor(address _owner, address _addressProvider) Ownable(_owner) {
        addressProvider = AddressProvider(_addressProvider);
    }

    function withdraw(address _token, uint256 _amount, address _receiver) public onlyOwner {
        IERC20(_token).transfer(_receiver, _amount);
    }

    function buy(address _token, uint256 _amount) public onlyOwner {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        UniExecutor uniExecutor = UniExecutor(addressProvider.getAddress("UniExecutor"));
        IERC20(_token).approve(address(uniExecutor), _amount);
        uniExecutor.swap(true, _amount, _token);
    }

    function sell(address _token, uint256 _amount) public onlyOwner {
        UniExecutor uniExecutor = UniExecutor(addressProvider.getAddress("UniExecutor"));
        IERC20(_token).approve(address(uniExecutor), _amount);
        uint256 amountOut = uniExecutor.swap(false, _amount, _token);
        IERC20(addressProvider.getAddress("USDC")).transfer(msg.sender, amountOut);
    }

}