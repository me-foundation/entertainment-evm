// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PacksStorage.sol";
import {Errors} from "../../common/Errors.sol";
import {TokenRescuer} from "../../common/TokenRescuer.sol";

/// @title PacksTreasury
/// @notice Handles treasury management for Packs contract
/// @dev Abstract contract with treasury helpers - storage accessed from PacksStorage
abstract contract PacksTreasury is PacksStorage, TokenRescuer {
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event TreasuryWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    event EmergencyWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    
    // ============================================================
    // TREASURY LOGIC
    // ============================================================
    
    function _withdrawTreasury(uint256 amount) internal {
        if (amount == 0) revert Errors.WithdrawAmountZero();
        if (amount > treasuryBalance) revert Errors.WithdrawAmountExceedsTreasury();
        treasuryBalance -= amount;

        (bool success,) = payable(fundsReceiver).call{value: amount}("");
        if (!success) revert Errors.WithdrawalFailed();

        emit TreasuryWithdrawal(msg.sender, amount, fundsReceiver);
    }
    
    function _emergencyWithdraw() internal virtual {
        treasuryBalance = 0;
        commitBalance = 0;
        protocolBalance = 0;

        uint256 currentBalance = address(this).balance;
        _rescueETH(fundsReceiver, currentBalance);
        // Pause must be called by inheriting contract that has PausableUpgradeable
        _pauseAfterEmergency();
        emit EmergencyWithdrawal(msg.sender, currentBalance, fundsReceiver);
    }
    
    function _pauseAfterEmergency() internal virtual;
}
