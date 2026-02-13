//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AddressProvider } from "../../config/AddressProvider.sol";
import { Roles } from "../../../security/Roles.sol";
import { SendraToken } from "../sendraTokens/SendraTokens.sol";

contract SendraErc20Minter {

    AddressProvider public immutable addressProvider;
    Roles public immutable roles;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        roles = Roles(addressProvider.getAddress("Roles"));
        SendraToken sendraBtc = new SendraToken(_addressProvider, 8, "SendraBtc", "sndBTC");
        SendraToken sendraEth = new SendraToken(_addressProvider, 18, "SendraEth", "sndETH");
        SendraToken sendraLink = new SendraToken(_addressProvider, 18, "SendraLink", "sndLINK");
        SendraToken sendraAave = new SendraToken(_addressProvider, 18, "SendraAave", "sndAAVE");
        SendraToken sendraUni = new SendraToken(_addressProvider, 18, "SendraUni", "sndUNI");
        addSendraToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, address(sendraBtc));
        addSendraToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, address(sendraEth)); // CAMBIAR ADDRESSES
        addSendraToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, address(sendraLink)); // CAMBIAR ADDRESSES
        addSendraToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, address(sendraAave)); // CAMBIAR ADDRESSES
        addSendraToken(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, address(sendraUni)); // CAMBIAR ADDRESSES
    }

    modifier onlyAdmin() {
        if(!roles.checkAdmin(msg.sender)) revert SenderNotAllowed();
        _;
    }

    modifier onlyProtocol() {
        if(!roles.isProtocolContract(msg.sender)) revert SenderNotAllowed();
        _;
    }


    mapping(address => address) public sendraTokens; // arbitrum erc20 => sendraToken

    function addSendraToken(address _token, address _sendraToken) internal {
        sendraTokens[_token] = _sendraToken;
    }

    function deploySendraToken(address tokenAddress, uint8 decimals, string memory name, string memory symbol) public onlyAdmin {
        address sendraTokenAddress = address(new SendraToken(address(addressProvider), decimals, name, symbol));
        addSendraToken(tokenAddress, sendraTokenAddress);
    }

    function mintSendraToken(address token, address to, uint256 amount) public onlyProtocol {
        SendraToken(sendraTokens[token]).mint(to, amount);
    }

    function burnSendraToken(address token, address from, uint256 amount) public onlyProtocol {
        SendraToken(sendraTokens[token]).burn(from, amount);
    }

    function getSendraToken(address token) public view returns (address) {
        return sendraTokens[token];
    }

    error SenderNotAllowed();

}