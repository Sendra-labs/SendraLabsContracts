/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒        UNISWAP EXECUTOR                                                                                                                                   
________________________________________________________________
*/


//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AddressProvider } from "../../config/AddressProvider.sol";
import { PoolRegistry } from "../config/PoolRegistry.sol";
import { ProtocolStorage } from "../../ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { HoldingsStorage } from "../storage/HoldingsStorage.sol";
import { HoldingsPositionManager } from "./HoldingsPositionManager.sol";
import { SecureAccount } from "../Accounts/SecureAccount.sol";
import { SendraErc20Minter } from "./SendraErc20Minter.sol";
import { ChainLinkPrices } from "../../../periphery/utils/ChainLinkPrices.sol";

contract UniExecutor is ReentrancyGuard {

    AddressProvider public immutable addressProvider;
    ISwapRouter public swapRouter;
    IQuoter public quoter;
    PoolRegistry public poolRegistry;
    IERC20 public immutable USDC;

    /// @notice Slippage tolerance in basis points (e.g. 50 = 0.5%)
    uint256 public constant SLIPPAGE_BPS = 50;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        swapRouter = ISwapRouter(addressProvider.getAddress("SwapRouter"));
        quoter = IQuoter(addressProvider.getAddress("Quoter"));
        poolRegistry = PoolRegistry(addressProvider.getAddress("PoolRegistry"));
        USDC = IERC20(addressProvider.getAddress("USDC"));
    }

    function swap(bool isBuy, uint256 _amountIn, address _token) public nonReentrant returns(uint256 _amountOut) {
        if(isBuy){
            USDC.transferFrom(msg.sender, address(this), _amountIn);
            USDC.approve(address(swapRouter), _amountIn);
        } else {
            IERC20(_token).transferFrom(msg.sender, address(this), _amountIn);
            IERC20(_token).approve(address(swapRouter), _amountIn);
        }
        (bytes memory buyPath, bytes memory sellPath) = poolRegistry.getSwapData(_token);
        bytes memory path = isBuy ? buyPath : sellPath;

        uint256 amountOutMinimum = _getAmountOutMinimum(path, _amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum
        });

        _amountOut = swapRouter.exactInput(params);
        address user = SecureAccount(msg.sender).owner();
        if(isBuy) SendraErc20Minter(addressProvider.getAddress("SendraErc20Minter")).mintSendraToken(_token, user, _amountOut);
        if(!isBuy) SendraErc20Minter(addressProvider.getAddress("SendraErc20Minter")).burnSendraToken(_token, user, _amountIn);
        uint256 price = ChainLinkPrices(addressProvider.getAddress("UtilsPrices")).getPrice(_token);
        
        HoldingsStorage holdingsStorage = HoldingsStorage(addressProvider.getAddress("HoldingsStorage"));
        uint256 positionId = holdingsStorage.getPositionId(user);
        
        ProtocolStorage protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(user, positionId);
        bytes[] memory positionData = position.positionData;
        
        bytes[] memory txsData = new bytes[](7);
        txsData[0] = abi.encode(isBuy ? _amountIn + abi.decode(positionData[0], (uint256)) : 0);
        txsData[1] = abi.encode(isBuy ? 0 : _amountOut + abi.decode(positionData[1], (uint256)));
        txsData[2] = abi.encode(isBuy ? _amountOut + abi.decode(positionData[2], (uint256)) : 0);
        txsData[3] = abi.encode(isBuy ? calculateAveragePrice(price, abi.decode(positionData[3], (uint256)), abi.decode(positionData[2], (uint256)), _amountOut) : 0);
        txsData[4] = abi.encode(isBuy ? 0 : calculateAveragePrice(price, abi.decode(positionData[4], (uint256)), abi.decode(positionData[7], (uint256)), _amountIn));
        txsData[5] = abi.encode(isBuy ? price : 0);
        txsData[6] = abi.encode(isBuy ? 0 : price);
        txsData[7] = abi.encode(isBuy ? 0 : _amountOut);
        managePosition(txsData, _token, user, isBuy, positionId);
        return _amountOut;
    }

    function calculateAveragePrice(
        uint256 _price, 
        uint256 _averagePrice, 
        uint256 _amountToken, 
        uint256 _valueChange
    ) internal pure returns (uint256) {
        return (
            _averagePrice == 0 ? _price : (_averagePrice * _amountToken + _price * _valueChange) / (_amountToken + _valueChange)
        );
    }
    
    function managePosition(bytes[] memory _values, address _token, address _user, bool _isBuy, uint256 _positionId) internal {
        uint256 i = 0;
        if(_token == 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f) { // WBTC
            i = 0;
        } else if(_token == 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) { // WETH
            // i = tokenNumber (BTC = 0; ETH = 1...) + elements each token has (currently 7 elements per token)
        }
        
        address positionManager = addressProvider.getAddress("HoldingsPositionManager");

        for(uint256 j = 0; j < _values.length; j++) {
            if(_isBuy){
                if(j == 0 || j == 2 || j == 3 || j == 5){
                    HoldingsPositionManager(positionManager).managePosition(
                        _positionId, 
                        i, 
                        _values[j], 
                        _user
                    );
                }
            } else {
                if(j == 1 || j == 4 || j == 6 || j == 7){
                    HoldingsPositionManager(positionManager).managePosition(
                        _positionId, 
                        i, 
                        _values[j], 
                        _user
                    );
                }
            }
            i++;
        }
    }

    /// @notice Gets expected output from Quoter and applies slippage tolerance
    function _getAmountOutMinimum(bytes memory path, uint256 amountIn) internal returns (uint256) {
        uint256 amountOut = quoter.quoteExactInput(path, amountIn);
        return amountOut * (10000 - SLIPPAGE_BPS) / 10000;
    }

}