//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";
import { PositionInitializer } from "../../bundles/executors/PositionInitializer.sol";
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
                    amount0Min: (_input.amount0 * 99) / 100, // 1% slippage
                    amount1Min: (_input.amount1 * 99) / 100, // 1% slippage
                    recipient: _input.recipient,
                    deadline: block.timestamp + 60
                }
            );

        (uint256 tokenId,,,) = positionManager.mint{ value : 0 }(params);

        bytes[] memory positionData = new bytes[](10);
        positionData[0] = abi.encode(_input.token0);
        positionData[1] = abi.encode(_input.token1);
        positionData[2] = abi.encode(block.timestamp);
        positionData[3] = abi.encode(_input.fee);
        positionData[4] = abi.encode(_input.tickLower);
        positionData[5] = abi.encode(_input.tickUpper);
        positionData[6] = abi.encode(_input.amount0);
        positionData[7] = abi.encode(_input.amount1);
        positionData[8] = abi.encode(_input.recipient);
        positionData[9] = abi.encode(tokenId);

        PositionInitializer positionInitializer = PositionInitializer(addressProvider.getAddress("PositionInitializer"));
        positionInitializer.initializePosition(positionData, 2, _input.recipient);
    }

    function withdrawLiquidityV3(UniswapLib.WithdrawLiquidityInput calldata _input) public {
        
        positionManager.transferFrom(msg.sender, address(this), _input.uniId);

        ProtocolLib.Position memory position = protocolStorage.getUserPositionById(_input.user, _input.positionId);
        
        address pool = factory.getPool(abi.decode(position.positionData[0], (address)), abi.decode(position.positionData[1], (address)), abi.decode(position.positionData[3], (uint24)));
        (uint160 sqrtCurrentPrice,,,,,, ) = IUniswapV3Pool(pool).slot0();
        (,, , , , , , uint128 liquidity, , , ,) = positionManager.positions(_input.uniId);
        
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
        
        positionManager.decreaseLiquidity{ value : 0 }(params);

        positionManager.transferFrom(address(this), msg.sender, _input.uniId);
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