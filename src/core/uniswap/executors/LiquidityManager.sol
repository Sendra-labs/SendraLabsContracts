//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";

contract LiquidityManager {

    INonfungiblePositionManager public immutable positionManager;
    ProtocolStorage public immutable protocolStorage;

    constructor(address _positionManager, address _protocolStorage) {
        positionManager = INonfungiblePositionManager(_positionManager);
        protocolStorage = ProtocolStorage(_protocolStorage);
    }

    function addLiquidityV3(UniswapLib.ProvideLiquidityInput calldata _input) public {

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
                {
                    token0 : _input.token0,
                    token1 : _input.token1,
                    fee : _input.fee,
                    tickLower: _input.tickLower,
                    tickUpper: _input.tickUpper,
                    amount0Desired: _input.amount0,
                    amount1Desired: _input.amount1,
                    amount0Min: 0,
                    amount1Min: 0,
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

    function collectFeesV3(address token0, address token1) public returns (uint256 amount0, uint256 amount1) {}

    
}