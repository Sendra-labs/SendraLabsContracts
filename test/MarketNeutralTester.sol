//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PairTrading } from "../src/core/bundles/executors/PairTrading.sol";
import { PairTradingLib } from "../src/lib/PairTrading/PairTradingLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AddressProvider } from "../src/core/config/AddressProvider.sol";
import { ClosePositionCallbacks } from "../src/core/bundles/executors/callbacks/ClosePositionCallbacks.sol";

contract NewMarketNeutralTester {
    using SafeERC20 for IERC20;
    
    PairTrading public pairTrading;
    AddressProvider public addressProvider;
    ClosePositionCallbacks public closePositionCallbacks;

    address public immutable deployer;

    constructor(address _pairTrading) {
        pairTrading = PairTrading(_pairTrading);
        deployer = msg.sender;
    }

    modifier onlyDeployer() {
        require(msg.sender == deployer, "Only deployer");
        _;
    }

    function setMarketNeutral(address _pairTrading) external {
        pairTrading = PairTrading(_pairTrading);
    }

    function setContractsAddressProvAndMarkNeu(address _addressProvider) external {
        addressProvider = AddressProvider(_addressProvider);
        pairTrading = PairTrading(addressProvider.getAddress("PairTrading"));
    }

    // Test openEtherPairTrading
    function testOpenEtherMarketNeutral(
        string memory marketLong,
        string memory marketShort,
        uint256 totalEthAmount,
        uint256 sizeDeltaUsdLong,
        uint256 sizeDeltaUsdShort,
        uint256 executionFee,
        uint256 slippageBps
    ) external payable {
        PairTradingLib.EtherPairTradingInput memory input = PairTradingLib.EtherPairTradingInput({
            marketLong: marketLong,
            marketShort: marketShort,
            totalEthAmount: totalEthAmount,
            sizeDeltaUsdLong: sizeDeltaUsdLong,
            sizeDeltaUsdShort: sizeDeltaUsdShort,
            executionFee: executionFee,
            slippageBps: slippageBps
        });
        
        pairTrading.openEtherPairTrading{value: msg.value}(input);
    }

    // Test openPositionWithEther (one side)
    function testOpenPositionWithEther(
        uint256 ethAmount,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 value,
        string memory market,
        bool isLong,
        address receiver
    ) external payable {
        PairTradingLib.EtherOneSideTradeInput memory input = PairTradingLib.EtherOneSideTradeInput({
            ethAmount: ethAmount,
            sizeDeltaUsd: sizeDeltaUsd,
            acceptablePrice: acceptablePrice,
            executionFee: executionFee,
            value: value,
            market: market,
            isLong: isLong,
            receiver: receiver
        });
        
        pairTrading.openPositionWithEther{value: msg.value}(input);
    }

    // Test openUSDCPairTrading
    function testOpenUSDCMarketNeutral(
        string memory marketLong,
        string memory marketShort,
        uint256 totalUsdcAmount,
        uint256 sizeDeltaUsdLong,
        uint256 sizeDeltaUsdShort,
        uint256 executionFee,
        uint256 slippageBps
    ) external payable {
        address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        IERC20(usdc).transferFrom(msg.sender, address(this), totalUsdcAmount);
        IERC20(usdc).approve(address(pairTrading), totalUsdcAmount);
        PairTradingLib.UsdcPairTradingInput memory input = PairTradingLib.UsdcPairTradingInput({
            marketLong: marketLong,
            marketShort: marketShort,
            totalUsdcAmount: totalUsdcAmount,
            sizeDeltaUsdLong: sizeDeltaUsdLong,
            sizeDeltaUsdShort: sizeDeltaUsdShort,
            executionFee: executionFee,
            slippageBps: slippageBps
        });
        
        // msg.value debe ser executionFee * 2 (uno para cada lado)
        require(msg.value >= executionFee * 2, "Insufficient msg.value");
        pairTrading.openUSDCPairTrading{value: msg.value}(input);
    }

    // Test openPositionWithUSDC (one side)
    function testOpenPositionWithUSDC(
        uint256 usdcAmount,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 executionFee,
        uint256 value,
        string memory market,
        bool isLong,
        address receiver
    ) external payable {
        PairTradingLib.UsdcOneSideTradeInput memory input = PairTradingLib.UsdcOneSideTradeInput({
            usdcAmount: usdcAmount,
            sizeDeltaUsd: sizeDeltaUsd,
            acceptablePrice: acceptablePrice,
            executionFee: executionFee,
            value: value,
            market: market,
            isLong: isLong,
            receiver: receiver
        });
        
        pairTrading.openPositionWithUSDC{value: msg.value}(input);
    }

    // Test closePairTrading
    function testCloseMarketNeutral(
        uint256 positionId,
        uint256 executionFee,
        uint256 slippageBps
    ) external payable {
        PairTradingLib.ClosePairTradingInput memory input = PairTradingLib.ClosePairTradingInput({
            positionId: positionId,
            executionFee: executionFee,
            slippageBps: slippageBps
        });
        
        pairTrading.closePairTrading{value: msg.value}(input);
    }

    // Test closeSidePairTrading
    function testCloseSideMarketNeutral(
        uint256 positionId,
        uint256 executionFee,
        uint256 slippageBps,
        uint256 value,
        bool isLongSide
    ) external payable {
        PairTradingLib.CloseSidePairTradingInput memory input = PairTradingLib.CloseSidePairTradingInput({
            positionId: positionId,
            executionFee: executionFee,
            slippageBps: slippageBps,
            value: value,
            isLongSide: isLongSide
        });
        
        pairTrading.closeSidePairTrading{value: msg.value}(input);
    }

    // Helper: Calculate leverage
    function calculateLeverage(uint256 collateralAmount, uint256 sizeDeltaUsd) external view returns (uint256) {
        return pairTrading.calculateLeverage(collateralAmount, sizeDeltaUsd);
    }

    // Helper: Calculate collateral for leverage
    function calculateCollateralForLeverage(uint256 sizeDeltaUsd, uint256 leverage) external view returns (uint256) {
        return pairTrading.calculateCollateralForLeverage(sizeDeltaUsd, leverage);
    }

    // Helper: Calculate position key
    function calculatePositionKey(
        address account,
        address market,
        address collateralToken,
        bool isLong
    ) external view returns (bytes32) {
        return pairTrading.calculatePositionKey(account, market, collateralToken, isLong);
    }

    // Withdraw tokens (only deployer)
    function withdrawTokens(address token, address to, uint256 amount) external onlyDeployer {
        require(to != address(0), "Invalid address");
        IERC20(token).safeTransfer(to, amount);
    }

    // Withdraw ETH (only deployer)
    function withdrawETH(address payable to, uint256 amount) external onlyDeployer {
        require(to != address(0), "Invalid address");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // Receive ETH
    receive() external payable {}

    function rescueFromCallback(string calldata token, uint256 amount) external onlyDeployer {
        address payable addressCallback = payable(addressProvider.getAddress("ClosePositionCallbacks"));
        address tokenAddress = bytes32(keccak256(bytes(token))) == bytes32(keccak256(bytes("ETH"))) ? address(0) : addressProvider.getAddress(token);
        ClosePositionCallbacks(addressCallback).emergencyWithdraw(tokenAddress, msg.sender, amount, "Rescue from callback");
    }

    function rescueFromCallbackAddress(address tokenAddress, uint256 amount) external onlyDeployer {
        address payable addressCallback = payable(addressProvider.getAddress("ClosePositionCallbacks"));
        ClosePositionCallbacks(addressCallback).emergencyWithdraw(tokenAddress, msg.sender, amount, "Rescue from callback");
    }

}
