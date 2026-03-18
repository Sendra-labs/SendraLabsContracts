//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityManager {

    INonfungiblePositionManager public immutable positionManager;
    ProtocolStorage public immutable protocolStorage;

    constructor(address _positionManager, address _protocolStorage) {
        positionManager = INonfungiblePositionManager(_positionManager);
        protocolStorage = ProtocolStorage(_protocolStorage);
    }

    function addLiquidityV3(UniswapLib.ProvideLiquidityInput calldata _input) public {
        
        IERC20(_input.token0).approve(address(positionManager), _input.amount0);
        IERC20(_input.token1).approve(address(positionManager), _input.amount1);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
                {
                    token0 : _input.token0,
                    token1 : _input.token1,
                    fee : _input.fee,
                    tickLower: _input.tickLower,
                    tickUpper: _input.tickUpper,
                    amount0Desired: _input.amount0,
                    amount1Desired: _input.amount1,
                    amount0Min: _input.amount0 * 99 / 100, // 1% slippage
                    amount1Min: _input.amount1 * 99 / 100, // 1% slippage
                    recipient: _input.recipient,
                    deadline: block.timestamp + 60
                }
            );

            (uint256 tokenId,,,) = positionManager.mint{ value : 0 }(params);

    }

    function removeLiquidityV3(address _user, uint256 positionId, uint256 tokenId, uint128 liquidity) public returns (uint256 amount0, uint256 amount1) {

        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_user, positionId);
        uint160 sqrtCurrentPrice = 10000;
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtCurrentPrice,
            TickMath.getSqrtRatioAtTick(int24(abi.decode(position.positionData[0], (int24)))), // CHECK
            TickMath.getSqrtRatioAtTick(int24(abi.decode(position.positionData[1], (int24)))),
            liquidity
        );
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =  INonfungiblePositionManager.DecreaseLiquidityParams( 
            {
                tokenId : tokenId,
                liquidity: liquidity,
                amount0Min : (_amount0*99)/100, //1% Slippage
                amount1Min : (_amount1*99)/100,
                deadline : block.timestamp + 20
            }
        );
        positionManager.decreaseLiquidity{ value : 0 }(params);

    }

    struct CollectParams {
        uint128 x;
    }

    function collectFeesV3(CollectParams calldata _input) public returns (uint256 amount0, uint256 amount1) {
        positionManager.transferFrom(msg.sender, address(this), 0/*uniId*/);
        positionManager.approve(address(positionManager), 0/*uniId*/);
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            0,//uniId,
            msg.sender,
            type(uint128).max,
            type(uint128).max
        );
        (uint256 _amount0, uint256 _amount1) = positionManager.collect{ value : 0 }(params);
        //IERC20(data.getPairData(pairId).tokenA).transfer(msg.sender, _amount0);
        //IERC20(data.getPairData(pairId).tokenB).transfer(msg.sender, _amount1);
        return(amount0, amount1);
    }

    
}