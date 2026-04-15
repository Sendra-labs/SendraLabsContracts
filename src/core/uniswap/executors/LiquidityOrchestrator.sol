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
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒    Liquidity Orchestrator                                                                                                                                   
________________________________________________________________
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { LiquidityManager } from "./LiquidityManager.sol";
import { SwapRouter } from "./SwapRouter.sol";
import { UniswapLib } from "../../../lib/uniswap/Uniswap.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { AddressProvider } from "../../../core/config/AddressProvider.sol";
import { PositionInitializer } from "../../bundles/executors/PositionInitializer.sol";
import { SendraStorage } from "../../SendraStorage.sol";
import { SendraLib } from "../../../lib/Sendra.lib.sol";

contract LiquidityOrchestrator {
    using SafeERC20 for IERC20;

    AddressProvider public immutable addressProvider;
    LiquidityManager public immutable liquidityManager;
    SwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    SendraStorage public immutable sendraStorage;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        liquidityManager = LiquidityManager(addressProvider.getAddress("LiquidityManager"));
        swapRouter = SwapRouter(addressProvider.getAddress("SwapRouter"));
        positionManager = INonfungiblePositionManager(addressProvider.getAddress("UniswapNFTPositionManager"));
        sendraStorage = SendraStorage(addressProvider.getAddress("SendraStorage"));
    }

    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata _input) public {
        UniswapLib.SwapInput memory swapInput0 = _input.swapInput0;
        UniswapLib.SwapInput memory swapInput1 = _input.swapInput1;
        UniswapLib.ProvideLiquidityInput memory provideLiquidityInput = _input.provideLiquidityInput;

        uint8[] memory gFieldIds = new uint8[](5);
        int256[] memory gDeltas = new int256[](5);

        uint8[] memory sFieldIds = new uint8[](2);
        int256[] memory sDeltas = new int256[](2);

        if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV3){
            
            bool isSwapNeeded0 = swapInput0.tokenIn != swapInput0.tokenOut;
            bool isSwapNeeded1 = swapInput1.tokenIn != swapInput1.tokenOut;


            IERC20(swapInput0.tokenIn).safeTransferFrom(
                msg.sender,
                isSwapNeeded0 ? address(swapRouter) : address(liquidityManager),
                swapInput0.amountIn0
            );

            IERC20(swapInput1.tokenIn).safeTransferFrom(
                msg.sender,
                isSwapNeeded1 ? address(swapRouter) : address(liquidityManager),
                swapInput1.amountIn0
            );

            uint256 totalUsdcAmountInput = swapInput0.amountIn0 + swapInput1.amountIn0;
            
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
                address pool,
                uint256 amountLeftToken0,
                uint256 amountLeftToken1
            ) = liquidityManager.addLiquidityV3(provideLiquidityInput);

            uint256 prevUsdcBalance = IERC20(swapInput0.tokenIn).balanceOf(address(this));

            // swapInput0/swapInput1 are not guaranteed to be aligned with token0/token1.
            // Map by tokenOut so we invert the correct route for each leftover.
            UniswapLib.SwapInput memory swapIntoToken0 =
                (swapInput0.tokenOut == provideLiquidityInput.token0) ? swapInput0 : swapInput1;
            UniswapLib.SwapInput memory swapIntoToken1 =
                (swapInput0.tokenOut == provideLiquidityInput.token1) ? swapInput0 : swapInput1;

            if (amountLeftToken0 > 0) {
                IERC20(provideLiquidityInput.token0).safeTransfer(address(swapRouter), amountLeftToken0);
                swapRouter.executeSwap(invertSwapInput(swapIntoToken0, amountLeftToken0));
            }
            if (amountLeftToken1 > 0) {
                IERC20(provideLiquidityInput.token1).safeTransfer(address(swapRouter), amountLeftToken1);
                swapRouter.executeSwap(invertSwapInput(swapIntoToken1, amountLeftToken1));
            }

            uint256 leftUsdc = IERC20(swapInput0.tokenIn).balanceOf(address(this)) - prevUsdcBalance;

            uint256 initialPositionUsdcValue = totalUsdcAmountInput - leftUsdc;

            IERC20(swapInput0.tokenIn).safeTransfer(msg.sender, leftUsdc);

            bytes[] memory positionData = new bytes[](18);
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
            positionData[15] = abi.encode(initialPositionUsdcValue);
            positionData[16] = abi.encode(0); // final date
            positionData[17] = abi.encode(100); // chainId

            // [0] = token0
            // [1] = token1
            // [2] = openDate
            // [3] = fee
            // [4] = tickLower
            // [5] = tickUpper
            // [6] = amountDeposited0 token0
            // [7] = amountDeposited1 token1
            // [8] = recipient
            // [9] = tokenId
            // [10] = initial pool price
            // [11] = pool
            // [12] = finalUsdValue
            // [13] = finalPoolPrice
            // [14] = feesCollectedUSD
            // [15] = initialPositionUsdcValue
            // [16] = final date
            // [17] = chainId

            gFieldIds[0] = 0;
            gDeltas[0] = int256(initialPositionUsdcValue);

            gFieldIds[1] = 2;
            uint256 peakExposure = uint256(sendraStorage.getUniqueGlobalAccumulator(2, _input.provideLiquidityInput.user));
            uint256 currentExposure = uint256(sendraStorage.getUniqueGlobalAccumulator(3, _input.provideLiquidityInput.user));
            uint256 newExposure = currentExposure + initialPositionUsdcValue;
            uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, _input.provideLiquidityInput.user));
            gDeltas[1] = newExposure > peakExposure ? int256(newExposure - peakExposure) : int256(0);

            gFieldIds[2] = 3;
            gDeltas[2] = int256(initialPositionUsdcValue);

            gFieldIds[3] = 9;
            gDeltas[3] = 1;

            gFieldIds[4] = 15;
            gDeltas[4] = int256(block.timestamp - lastActivityTimestamp);

            sFieldIds[0] = 1;
            sDeltas[0] = int256(initialPositionUsdcValue);

            sFieldIds[1] = 5;
            sDeltas[1] = 1;


            PositionInitializer positionInitializer = PositionInitializer(addressProvider.getAddress("PositionInitializer"));
            positionInitializer.initializePosition(positionData, 2, _input.provideLiquidityInput.user);

        } else if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV4){
            //TODO: Implement UniswapV4
        }

        updateAccumulators(gFieldIds, gDeltas, 2, sFieldIds, sDeltas);
    }

    function updateAccumulators(uint8[] memory _gFieldIds, int256[] memory _gDeltas, uint64 _specificKey, uint8[] memory _sFieldIds, int256[] memory _sDeltas) internal {
        sendraStorage.applyGlobalPulseDeltas(msg.sender, _gFieldIds, _gDeltas);
        sendraStorage.applySpecificPulseDeltas(msg.sender, _specificKey, _sFieldIds, _sDeltas);
    }

    function invertSwapInput(UniswapLib.SwapInput memory _input, uint256 _amount)
        public
        view
        returns (UniswapLib.SwapInput memory)
    {
        uint256 len = _input.swapInstructions.length;

        UniswapLib.SwapInstruction[] memory invertedInstructions = new UniswapLib.SwapInstruction[](len);
        for (uint256 i = 0; i < len; i++) {
            UniswapLib.SwapInstruction memory inst = _input.swapInstructions[len - 1 - i];

            address hopTokenIn = inst.tokenOut;
            address hopTokenOut = inst.tokenIn;

            invertedInstructions[i] = UniswapLib.SwapInstruction({
                protocol: inst.protocol,
                tokenIn: hopTokenIn,
                tokenOut: hopTokenOut,
                amountIn: (i == 0) ? _amount : 0,
                amountOut: 0,
                poolOrPair: inst.poolOrPair,
                fee: inst.fee,
                poolKey: inst.poolKey
            });
        }

        return UniswapLib.SwapInput({
            tokenIn: _input.tokenOut,
            tokenOut: _input.tokenIn,
            swapInstructions: invertedInstructions,
            amountIn0: _amount,
            to: address(this)
        });
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

        SendraLib.Position memory position = sendraStorage.getUserPositionById(_input.collectParams.user, _input.collectParams.positionId);
        position.positionData[14] = abi.encode(abi.decode(position.positionData[14], (uint256)) + amount); // feesCollectedUSD (base unit)
        sendraStorage.updateUserFullPosition(_input.collectParams.user, _input.collectParams.positionId, position);
        sendraStorage.applyMetricDelta(_input.collectParams.user, 2, 0, int256(amount));

        positionManager.transferFrom(address(this), msg.sender, _input.collectParams.uniId);
        return amount;
    }

    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input) public returns (uint256){
        
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.transferFrom(msg.sender, address(this), _input.withdrawLiquidityInput.uniId);

        UniswapLib.CollectParams memory _collectParams = UniswapLib.CollectParams(
            _input.withdrawLiquidityInput.uniId,
            _input.withdrawLiquidityInput.positionId,
            false,
            _input.withdrawLiquidityInput.user
        );

        UniswapLib.ExecuteCollectFeesOnly memory executeCollectFeesOnly = UniswapLib.ExecuteCollectFeesOnly(
            _collectParams,
            _input.swapInput0,
            _input.swapInput1
        );

        uint256 feesCollectedUsdc = collectFees(executeCollectFeesOnly);

        positionManager.approve(address(liquidityManager), _input.withdrawLiquidityInput.uniId);
        (SendraLib.Position memory position, uint160 sqrtCurrentPrice) = liquidityManager.withdrawLiquidityV3(_input.withdrawLiquidityInput);
        
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
        position.pnl = int256(amountUsdcReceived) - int256(abi.decode(position.positionData[15], (uint256)));

        position.positionData[12] = abi.encode(amountUsdcReceived);
        position.positionData[13] = abi.encode(sqrtCurrentPrice); // finalPoolPrice
        position.positionData[14] = abi.encode(feesCollectedUsdc); // feesCollectedUSD
        position.positionData[16] = abi.encode(block.timestamp); // final date
        sendraStorage.decreaseGlobalPositionActivePositions(msg.sender);

        sendraStorage.updateUserFullPosition(msg.sender, _input.withdrawLiquidityInput.positionId, position);

        uint8[] memory gFieldIds = new uint8[](13);
        int256[] memory gDeltas = new int256[](13);

        uint8[] memory sFieldIds = new uint8[](3);
        int256[] memory sDeltas = new int256[](3);

        gFieldIds[0] = 1;
        gDeltas[0] = int256(amountUsdcReceived);
        gFieldIds[1] = 3;
        gDeltas[1] = -int256(abi.decode(position.positionData[15], (uint256)));
        gFieldIds[2] = 4;
        gDeltas[2] = int256(position.pnl);
        int256 highWaterMark = sendraStorage.getUniqueGlobalAccumulator(7, _input.withdrawLiquidityInput.user);
        int256 currentPnl = sendraStorage.getUniqueGlobalAccumulator(4, _input.withdrawLiquidityInput.user);
        int256 newPnl = currentPnl + position.pnl;
        int256 maxDrawdown = sendraStorage.getUniqueGlobalAccumulator(8, _input.withdrawLiquidityInput.user);
        int256 consecutiveLosses = sendraStorage.getUniqueGlobalAccumulator(17, _input.withdrawLiquidityInput.user);
        int256 maxConsecutiveLosses = sendraStorage.getUniqueGlobalAccumulator(18, _input.withdrawLiquidityInput.user);
        uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, _input.withdrawLiquidityInput.user));
        gFieldIds[4] = 7;
        gFieldIds[5] = 8;
        gFieldIds[6] = 10;
        gDeltas[6] = 1;
        gFieldIds[7] = 11;
        gFieldIds[8] = 12;

        if(position.pnl > 0) {
            gFieldIds[3] = 5;
            gDeltas[3] = int256(position.pnl);
            gDeltas[4] = highWaterMark < newPnl ? int256(newPnl - highWaterMark) : int256(0);
            gDeltas[5] = 0;
            gDeltas[7] = 1;
            gDeltas[8] = 0;
        } else {
            gFieldIds[3] = 6;
            gDeltas[3] = -int256(position.pnl);
            gDeltas[4] = int256(0);
            int256 drawdown = (newPnl < highWaterMark) ? int256(highWaterMark - newPnl) : int256(0);
            gDeltas[5] = maxDrawdown < drawdown ? drawdown - maxDrawdown : int256(0);
            gDeltas[7] = 0;
            gDeltas[8] = 1;
        }

        gFieldIds[9] = 13;
        gDeltas[9] = int256(block.timestamp - abi.decode(position.positionData[2], (uint256)));

        gFieldIds[10] = 15;
        gDeltas[10] = int256(block.timestamp - lastActivityTimestamp);

        gFieldIds[11] = 17;
        gFieldIds[12] = 18;
        if(position.pnl < 0) {
            int256 newStreak = consecutiveLosses + 1;
            gDeltas[11] = int256(1); // consecutiveLosses += 1
            gDeltas[12] = newStreak > maxConsecutiveLosses ? int256(newStreak - maxConsecutiveLosses) : int256(0);
        } else if(position.pnl > 0) {
            gDeltas[11] = consecutiveLosses > 0 ? -consecutiveLosses : int256(0); // reset to 0 on win
            gDeltas[12] = int256(0);
        }

        sFieldIds[0] = 0;
        sDeltas[0] = int256(position.pnl);
        sFieldIds[1] = 2;
        sDeltas[1] = int256(amountUsdcReceived);

        if(position.pnl > 0) {
            sFieldIds[2] = 3;
            sDeltas[2] = int256(1);
        } else if(position.pnl < 0) {
            sFieldIds[2] = 4;
            sDeltas[2] = int256(-1);
        }

        sendraStorage.applyMetricDelta(msg.sender, 2, 0, int256(feesCollectedUsdc)); // feesCollectedUSD (base unit)
        sendraStorage.applyMetricDelta(msg.sender, 2, 1, int256(block.timestamp - abi.decode(position.positionData[2], (uint256)))); // liquiditySeconds

        updateAccumulators(gFieldIds, gDeltas, 2, sFieldIds, sDeltas);

        return amountUsdcReceived;
    }

    function collectFees(UniswapLib.ExecuteCollectFeesOnly memory _input) internal returns (uint256){
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

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

        return amount;
    }

}

/*
especificos para uniswap:
- pricePool inicial vs final... vemos la precision en los cierres...
- feesCollectedUSD (necesitamos un get currentPrice de Chainlink, no del pool por que puede ser contra ETH  en vez de contra USDC)
- tiempo medio de las posiciones de uniswap
- metrica de amplitud de rangos
- APR medio de las posiciones ? podemos sacarlo de fees collected y la cantidad de capital in
- tipos de estrategia:
    - closedOutOfRange & positivePnl (fees + marketUp)
    - closedOutOfRange & negativePnl (fees + marketDown)
    - closedInRange & positivePnl (fees + marketUp)
    - closedInRange & negativePnl (fees + marketDown)
- impermanent loss: ¿? ¿?
    - nos importa realmente? o solo nos interesa si ha ganado o ha perdido? el IL es muy subjetivo, es a pasado, en LP buscamos estrategiass pasivas sin depender tanto de la direccion del mercado 

    [0] = feesCollectedUSD // recibido tras swaps
    [1] = liquiditySeconds // tiempo que ha estado la posicion abierta. podemos usarlo para APRs
    [0] = feesCollectedUSD
    [0] = feesCollectedUSD
    [0] = feesCollectedUSD
*/