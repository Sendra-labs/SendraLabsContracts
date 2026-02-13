//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Roles } from "../../../security/Roles.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";

contract PoolRegistry {

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
        addSwapData(
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 
            abi.encodePacked(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, uint24(500), 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f), 
            abi.encodePacked(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, uint24(500), 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, uint24(500), 0xaf88d065e77c8cC2239327C5EDb3A432268e5831)
        ); // WBTC
    }

    modifier onlyAdmin() {
        if(!roles.checkAdmin(msg.sender)) revert SenderNotAllowed();
        _;
    }


    struct SwapData {
        bytes buyPath;
        bytes sellPath;
    }

    mapping(address => SwapData) public swapData;

    function addSwapData(address _token, bytes memory _buyPath, bytes memory _sellPath) public onlyAdmin {
        swapData[_token] = SwapData({
            buyPath: _buyPath,
            sellPath: _sellPath
        });
    }

    function getSwapData(address _token) public view returns(bytes memory, bytes memory){
        return (swapData[_token].buyPath, swapData[_token].sellPath);
    }

    error SenderNotAllowed();
    
}

/*
0x0E4831319A50228B9e450861297aB92dee15B44F BTC USDC POOL
*/