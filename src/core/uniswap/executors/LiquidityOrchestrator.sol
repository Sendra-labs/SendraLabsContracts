//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { LiquidityManager } from "./LiquidityManager.sol";
import { SwapRouter } from "./SwapRouter.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { PositionInitializer } from "../../bundles/executors/PositionInitializer.sol";
import { ProtocolStorage } from "../../../core/ProtocolStorage.sol";
import { ProtocolLib } from "../../../lib/Protocol.lib.sol";

contract LiquidityOrchestrator {

    AddressProvider public immutable addressProvider;
    LiquidityManager public immutable liquidityManager;
    SwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    ProtocolStorage public immutable protocolStorage;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        liquidityManager = LiquidityManager(addressProvider.getAddress("LiquidityManager"));
        swapRouter = SwapRouter(addressProvider.getAddress("SwapRouter"));
        positionManager = INonfungiblePositionManager(addressProvider.getAddress("UniswapNFTPositionManager"));
        protocolStorage = ProtocolStorage(addressProvider.getAddress("ProtocolStorage"));
    }

    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata _input) public {
        UniswapLib.SwapInput memory swapInput0 = _input.swapInput0;
        UniswapLib.SwapInput memory swapInput1 = _input.swapInput1;
        UniswapLib.ProvideLiquidityInput memory provideLiquidityInput = _input.provideLiquidityInput;

        if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV3){
            
            bool isSwapNeeded0 = swapInput0.tokenIn != swapInput0.tokenOut;
            bool isSwapNeeded1 = swapInput1.tokenIn != swapInput1.tokenOut;

            IERC20(swapInput0.tokenIn).transferFrom(
                msg.sender, 
                isSwapNeeded0 ? address(swapRouter) : address(liquidityManager), 
                swapInput0.amountIn0
            );

            IERC20(swapInput1.tokenIn).transferFrom(
                msg.sender, 
                isSwapNeeded1 ? address(swapRouter) : address(liquidityManager), 
                swapInput1.amountIn0
            );
            
            swapInput0.to = address(liquidityManager);
            swapInput1.to = address(liquidityManager);

            if(isSwapNeeded0) swapRouter.executeSwap(swapInput0);
            if(isSwapNeeded1) swapRouter.executeSwap(swapInput1);

            provideLiquidityInput.recipient = _input.isSendraRecipient ? address(this) : msg.sender;
            provideLiquidityInput.user = msg.sender;

            (
                uint256 tokenId, 
                uint256 amountDeposited0, 
                uint256 amountDeposited1, 
                uint160 sqrtCurrentPrice, 
                address pool
            ) = liquidityManager.addLiquidityV3(provideLiquidityInput);

            bytes[] memory positionData = new bytes[](15);
            positionData[0] = abi.encode(_input.provideLiquidityInput.token0);
            positionData[1] = abi.encode(_input.provideLiquidityInput.token1);
            positionData[2] = abi.encode(block.timestamp);
            positionData[3] = abi.encode(_input.provideLiquidityInput.fee);
            positionData[4] = abi.encode(_input.provideLiquidityInput.tickLower);
            positionData[5] = abi.encode(_input.provideLiquidityInput.tickUpper);
            positionData[6] = abi.encode(amountDeposited0);
            positionData[7] = abi.encode(amountDeposited1);
            positionData[8] = abi.encode(provideLiquidityInput.recipient);
            positionData[9] = abi.encode(tokenId);
            positionData[10] = abi.encode(sqrtCurrentPrice);
            positionData[11] = abi.encode(pool);
            positionData[12] = abi.encode(uint256(0)); // finalUsdValue
            positionData[13] = abi.encode(uint256(0)); // finalPoolPrice
            positionData[14] = abi.encode(uint256(0)); // feesCollectedUSD

            PositionInitializer positionInitializer = PositionInitializer(addressProvider.getAddress("PositionInitializer"));
            positionInitializer.initializePosition(positionData, 2, _input.provideLiquidityInput.user);

        } else if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV4){
            //TODO: Implement UniswapV4
        }
    }

    function collectFeesOnly(UniswapLib.ExecuteCollectFeesOnly calldata _input) public returns (uint256){
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.transferFrom(msg.sender, address(this), _input.collectParams.uniId);

        positionManager.approve(address(liquidityManager), _input.collectParams.uniId);
        (uint256 amount0, uint256 amount1) = liquidityManager.collectV3(_input.collectParams);

        bool isSwapNeeded0 = _input.swapInput0.tokenIn != _input.swapInput0.tokenOut;
        bool isSwapNeeded1 = _input.swapInput1.tokenIn != _input.swapInput1.tokenOut;

        if(isSwapNeeded0) {
            IERC20(_input.swapInput0.tokenIn).transfer(address(swapRouter), amount0);
            UniswapLib.SwapInput memory swap0 = _input.swapInput0;
            swap0.to = address(this);
            swap0.amountIn0 = amount0;
            if(swap0.swapInstructions.length > 0) swap0.swapInstructions[0].amountIn = amount0;
            swapRouter.executeSwap(swap0);
        }
        if(isSwapNeeded1) {
            IERC20(_input.swapInput1.tokenIn).transfer(address(swapRouter), amount1);
            UniswapLib.SwapInput memory swap1 = _input.swapInput1;
            swap1.to = address(this);
            swap1.amountIn0 = amount1;
            if(swap1.swapInstructions.length > 0) swap1.swapInstructions[0].amountIn = amount1;
            swapRouter.executeSwap(swap1);
        }

        uint256 newBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));
        uint256 amount = newBalance - prevBalance;
        IERC20(_input.swapInput0.tokenOut).transfer(msg.sender, amount);

        positionManager.transferFrom(address(this), msg.sender, _input.collectParams.uniId);
        return amount;
    }
    
    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input) public returns (uint256){
        
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.transferFrom(msg.sender, address(this), _input.withdrawLiquidityInput.uniId);

        positionManager.approve(address(liquidityManager), _input.withdrawLiquidityInput.uniId);
        (ProtocolLib.Position memory position, uint160 sqrtCurrentPrice) = liquidityManager.withdrawLiquidityV3(_input.withdrawLiquidityInput);
        
        UniswapLib.CollectParams memory collectParams = UniswapLib.CollectParams(
            _input.withdrawLiquidityInput.uniId,
            _input.withdrawLiquidityInput.positionId,
            true,
            _input.withdrawLiquidityInput.user
        );

        positionManager.approve(address(liquidityManager), _input.withdrawLiquidityInput.uniId);
        (uint256 amount0, uint256 amount1) = liquidityManager.collectV3(collectParams);
        
        bool isSwapNeeded0 = _input.swapInput0.tokenIn != _input.swapInput0.tokenOut;
        bool isSwapNeeded1 = _input.swapInput1.tokenIn != _input.swapInput1.tokenOut;

        if(isSwapNeeded0) {
            IERC20(_input.swapInput0.tokenIn).transfer(address(swapRouter), amount0);
            UniswapLib.SwapInput memory swap0 = _input.swapInput0;
            swap0.to = address(this);
            swap0.amountIn0 = amount0;
            if(swap0.swapInstructions.length > 0) swap0.swapInstructions[0].amountIn = amount0;
            swapRouter.executeSwap(swap0);
        }
        if(isSwapNeeded1) {
            IERC20(_input.swapInput1.tokenIn).transfer(address(swapRouter), amount1);
            UniswapLib.SwapInput memory swap1 = _input.swapInput1;
            swap1.to = address(this);
            swap1.amountIn0 = amount1;
            if(swap1.swapInstructions.length > 0) swap1.swapInstructions[0].amountIn = amount1;
            swapRouter.executeSwap(swap1);
        }

        uint256 newBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));
        uint256 amountUsdcReceived = newBalance - prevBalance;
        IERC20(_input.swapInput0.tokenOut).transfer(msg.sender, amountUsdcReceived);

        positionManager.transferFrom(address(this), msg.sender, _input.withdrawLiquidityInput.uniId);

        position.isActive = false;
        position.positionData[12] = abi.encode(amountUsdcReceived);
        position.positionData[13] = abi.encode(sqrtCurrentPrice); // finalPoolPrice
        protocolStorage.decreaseGlobalPositionActivePositions(msg.sender);

        protocolStorage.updateUserFullPosition(msg.sender, _input.withdrawLiquidityInput.positionId, position);

        return amountUsdcReceived;
    }

}