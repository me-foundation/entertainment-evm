// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Shared Errors
/// @notice Common error definitions used across multiple contracts
library Errors {
    // Generic errors (deprecated - use specific errors below)
    error InvalidAddress();
    error TransferFailed();
    error InvalidAmount();
    error InsufficientBalance();
    error ArrayLengthMismatch();
    error Unauthorized();
    
    // Specific amount errors
    error WithdrawAmountZero();
    error WithdrawAmountExceedsTreasury();
    error CommitAmountZero();
    error CommitAmountTooLowForFlatFee();
    error PackPriceBelowMinimum();
    error PackPriceAboveMaximum();
    error PayoutExceedsOrderAmount();
    error OrderAmountBelowBucketMin();
    error OrderAmountAboveBucketMax();
    error PayoutAmountBelowBucketMin();
    error PayoutAmountAboveBucketMax();
    
    // Specific balance errors
    error InsufficientTreasuryBalance();
    
    // Specific address errors
    error CosignerAddressZero();
    error NotActiveCosigner();
    error ReceiverAddressZero();
    error CosignerAddressZeroInCommit();
    error CosignerNotActive();
    error PackSignerMismatch();
    error PackSignerNotCosigner();
    error MarketplaceAddressZero();
    error CommitSignerMismatch();
    error CommitSignerNotCosigner();
    error FulfillmentSignerMismatch();
    error FulfillmentSignerNotCosigner();
    error FundsReceiverAddressZero();
    
    // Specific authorization errors
    error OnlyCosignerCanFulfill();
    
    // Packs contract-specific errors
    error AlreadyCosigner();
    error AlreadyFulfilled();
    error InvalidCommitOwner();
    error InvalidBuckets();
    error InvalidReward();
    error InvalidPackPrice();
    error InvalidCommitId();
    error WithdrawalFailed();
    error InvalidCommitCancellableTime();
    error InvalidCommitUserCancellableTime();
    error InvalidNftFulfillmentExpiryTime();
    error CommitIsCancelled();
    error CommitNotCancellable();
    error InvalidFundsReceiverManager();
    error BucketSelectionFailed();
    error InvalidProtocolFee();
}
