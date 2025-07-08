// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPayoutContract {
    function fulfillPayout(
        bytes32 orderHash,
        address receiver,
        uint256 receiverAmount,
        address feeReceiver,
        uint256 feeAmount
    ) external payable;
}

contract PayoutContract is IPayoutContract {
    event PayoutFulfilled(
        bytes32 indexed orderHash,
        address indexed receiver,
        address indexed feeReceiver,
        uint256 receiverAmount,
        uint256 feeAmount
    );
    
    error InvalidReceiver();
    error TransferFailed();
    error InsufficientFunds();
    
    function fulfillPayout(
        bytes32 orderHash,
        address receiver,
        uint256 receiverAmount,
        address feeReceiver,
        uint256 feeAmount
    ) external payable override {
        if (receiver == address(0)) revert InvalidReceiver();
        if (feeReceiver == address(0)) revert InvalidReceiver();
        if (msg.value < receiverAmount + feeAmount) revert InsufficientFunds();
        
        if (receiverAmount > 0) {
            (bool success, ) = payable(receiver).call{value: receiverAmount}("");
            if (!success) revert TransferFailed();
        }
        
        if (feeAmount > 0) {
            (bool feeSuccess, ) = payable(feeReceiver).call{value: feeAmount}("");
            if (!feeSuccess) revert TransferFailed();
        }
        
        emit PayoutFulfilled(
            orderHash,
            receiver,
            feeReceiver,
            receiverAmount,
            feeAmount
        );
    }
}