//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";

contract LiquidityManager {

    AddressProvider public immutable addressProvider;
    INonfungiblePositionManager public immutable positionManager;
    ProtocolStorage public immutable protocolStorage;
    IUniswapV3Factory public immutable factory;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        positionManager = INonfungiblePositionManager(addressProvider.getAddress("UniswapNFTPositionManager"));
        protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
        factory = IUniswapV3Factory(addressProvider.getAddress("UniswapV3Factory"));
    }

    function addLiquidityV3(UniswapLib.ProvideLiquidityInput calldata _input) public returns (uint256, uint256, uint256, uint160, address) {
        
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
                    amount0Min: (_input.amount0 * 85) / 100, // 15% slippage
                    amount1Min: (_input.amount1 * 85) / 100,
                    recipient: _input.recipient,
                    deadline: block.timestamp + 60
                }
            );

        (uint256 tokenId,, uint256 amountDeposited0, uint256 amountDeposited1) = positionManager.mint{ value : 0 }(params);

        uint256 amountLeftToken0 = IERC20(_input.token0).balanceOf(address(this));
        uint256 amountLeftToken1 = IERC20(_input.token1).balanceOf(address(this));
        if(amountLeftToken0 > 0) IERC20(_input.token0).transfer(_input.user, amountLeftToken0);
        if(amountLeftToken1 > 0) IERC20(_input.token1).transfer(_input.user, amountLeftToken1);

        address pool = factory.getPool(_input.token0, _input.token1, _input.fee);
        (uint160 sqrtCurrentPrice,,,,,, ) = IUniswapV3Pool(pool).slot0();

        return (tokenId, amountDeposited0, amountDeposited1, sqrtCurrentPrice, pool);
    }

    function withdrawLiquidityV3(UniswapLib.WithdrawLiquidityInput calldata _input) public returns (ProtocolLib.Position memory, uint160){
        
        positionManager.transferFrom(msg.sender, address(this), _input.uniId);

        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_input.user, _input.positionId);
        
        address pool = factory.getPool(abi.decode(position.positionData[0], (address)), abi.decode(position.positionData[1], (address)), abi.decode(position.positionData[3], (uint24)));
        (uint160 sqrtCurrentPrice,,,,,, ) = IUniswapV3Pool(pool).slot0();
        (,, , , , , , uint128 liquidity, , , uint256 feesCollectedToken0, uint256 feesCollectedToken1) = positionManager.positions(_input.uniId);
        
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtCurrentPrice,
            TickMath.getSqrtRatioAtTick(abi.decode(position.positionData[4], (int24))),
            TickMath.getSqrtRatioAtTick(abi.decode(position.positionData[5], (int24))),
            liquidity
        );
        
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =  INonfungiblePositionManager.DecreaseLiquidityParams( 
            {
                tokenId : _input.uniId,
                liquidity: liquidity,
                amount0Min : (_amount0*99)/100, //1% Slippage
                amount1Min : (_amount1*99)/100,
                deadline : block.timestamp + 60
            }
        );
        
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity{ value : 0 }(params);

        positionManager.transferFrom(address(this), msg.sender, _input.uniId);

        return (position, sqrtCurrentPrice);
    }

    function collectV3(UniswapLib.CollectParams calldata _input) public returns (uint256 amount0, uint256 amount1) {
      
        positionManager.transferFrom(msg.sender, address(this), _input.uniId);

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            _input.uniId,
            msg.sender,
            type(uint128).max,
            type(uint128).max
        );
       
        (amount0, amount1) = positionManager.collect{ value : 0 }(params);

        positionManager.transferFrom(address(this), msg.sender, _input.uniId);

        return(amount0, amount1);
    }

    
}