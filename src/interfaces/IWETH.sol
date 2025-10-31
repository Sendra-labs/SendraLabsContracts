//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IWETH
 * @notice Interface for Wrapped Ether (WETH) token
 * @dev Standard interface for WETH operations
 */
interface IWETH {
    /**
     * @notice Withdraw WETH and receive ETH
     * @param amount Amount of WETH to withdraw
     */
    function withdraw(uint256 amount) external;
    
    /**
     * @notice Deposit ETH and receive WETH
     */
    function deposit() external payable;
}
