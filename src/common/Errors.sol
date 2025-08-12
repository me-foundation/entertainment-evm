// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Shared Errors
/// @notice Common error definitions used across multiple contracts
library Errors {
    error InvalidAddress();
    error TransferFailed();
    error InvalidAmount();
    error InsufficientBalance();
    error ArrayLengthMismatch();
    error Unauthorized();
}
