// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PacksStorage.sol";
import {Errors} from "../../common/Errors.sol";

/// @title PacksCancel
/// @notice Handles cancellation flow logic for Packs contract
/// @dev Abstract contract with cancel helpers - storage accessed from PacksStorage
abstract contract PacksCancel is PacksStorage {
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event CommitCancelled(uint256 indexed commitId, bytes32 digest);
    event CancellationRefundFailed(uint256 indexed commitId, address indexed receiver, uint256 amount, bytes32 digest);
    
    // ============================================================
    // CANCEL LOGIC
    // ============================================================
    
    function _cancel(uint256 commitId_) internal {
        _validateCancellationRequest(commitId_);
        isCancelled[commitId_] = true;
        CommitData memory commitData = packs[commitId_];
        uint256 totalRefund = _calculateAndUpdateRefund(commitId_, commitData.packPrice);
        _processRefund(commitId_, commitData.receiver, totalRefund, commitData);
        emit CommitCancelled(commitId_, hashCommit(commitData));
    }
    
    function _validateCancellationRequest(uint256 commitId_) internal view {
        if (commitId_ >= packs.length) revert Errors.InvalidCommitId();
        if (isFulfilled[commitId_]) revert Errors.AlreadyFulfilled();
        if (isCancelled[commitId_]) revert Errors.CommitIsCancelled();
        if (block.timestamp < commitCancellableAt[commitId_]) {
            revert Errors.CommitNotCancellable();
        }
    }
    
    function _calculateAndUpdateRefund(uint256 commitId_, uint256 packPrice) internal returns (uint256 totalRefund) {
        commitBalance -= packPrice;
        uint256 protocolFeesPaid = feesPaid[commitId_];
        protocolBalance -= protocolFeesPaid;
        totalRefund = packPrice + protocolFeesPaid;
    }
    
    function _processRefund(uint256 commitId_, address receiver, uint256 amount, CommitData memory commitData) internal {
        (bool success,) = payable(receiver).call{value: amount}("");
        if (!success) {
            treasuryBalance += amount;
            emit CancellationRefundFailed(commitId_, receiver, amount, hashCommit(commitData));
        }
    }
}
