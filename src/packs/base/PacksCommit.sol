// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PacksStorage.sol";
import {Errors} from "../../common/Errors.sol";

/// @title PacksCommit
/// @notice Handles commit flow logic for Packs contract
/// @dev Abstract contract with commit helpers - storage accessed from PacksStorage
abstract contract PacksCommit is PacksStorage {
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        uint256 packPrice,
        bytes32 packHash,
        bytes32 digest,
        uint256 protocolFee,
        uint256 flatFee
    );    
    event CommitCancelled(uint256 indexed commitId, bytes32 digest);
    event CommitCancelledByUser(uint256 indexed commitId, bytes32 digest);
    event CancellationRefundFailed(uint256 indexed commitId, address indexed receiver, uint256 amount, bytes32 digest);
    
    // ============================================================
    // COMMIT LOGIC
    // ============================================================
    
    /// @notice Calculate contribution amount with custom fee rate
    function calculateContributionWithoutFee(
        uint256 amount,
        uint256 feeRate
    ) public pure returns (uint256) {
        return (amount * BASE_POINTS) / (BASE_POINTS + feeRate);
    }
    
    function _commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        PackType packType_,
        BucketData[] memory buckets_,
        bytes memory signature_
    ) internal returns (uint256) {
        uint256 packPrice = _validateAndCalculatePackPrice(msg.value);
        _validateCommitAddresses(receiver_, cosigner_);
        _validateBuckets(buckets_, packPrice);
        bytes32 packHash = _verifyPackSignature(packType_, packPrice, buckets_, signature_, cosigner_);
        uint256 commitId = _createCommit(receiver_, cosigner_, seed_, packPrice, buckets_, packHash);
        _processCommitFees(commitId, packPrice);
        _setCommitExpiryTimes(commitId);
        
        bytes32 digest = hashCommit(packs[commitId]);
        commitIdByDigest[digest] = commitId;
        
        emit Commit(
            msg.sender, commitId, receiver_, cosigner_, seed_, 
            packs[commitId].counter, packPrice, packHash, digest, 
            feesPaid[commitId], flatFee
        );
        
        return commitId;
    }
    
    function _validateAndCalculatePackPrice(uint256 totalAmount) internal view returns (uint256) {
        if (totalAmount == 0) revert Errors.CommitAmountZero();
        if (totalAmount <= flatFee) revert Errors.CommitAmountTooLowForFlatFee();
        
        uint256 packPrice = calculateContributionWithoutFee(totalAmount, protocolFee) - flatFee;
        
        if (packPrice < minPackPrice) revert Errors.PackPriceBelowMinimum();
        if (packPrice > maxPackPrice) revert Errors.PackPriceAboveMaximum();
        
        return packPrice;
    }
    
    function _validateCommitAddresses(address receiver_, address cosigner_) internal view {
        if (receiver_ == address(0)) revert Errors.ReceiverAddressZero();
        if (cosigner_ == address(0)) revert Errors.CosignerAddressZeroInCommit();
        if (!isCosigner[cosigner_]) revert Errors.CosignerNotActive();
    }
    
    function _validateBuckets(BucketData[] memory buckets_, uint256 packPrice) internal view {
        if (buckets_.length < MIN_BUCKETS) revert Errors.InvalidBuckets();
        if (buckets_.length > MAX_BUCKETS) revert Errors.InvalidBuckets();

        uint256 totalOdds = 0;
        for (uint256 i = 0; i < buckets_.length; i++) {
            _validateBucketValues(buckets_[i], packPrice);
            _validateBucketOdds(buckets_[i]);
            
            if (i < buckets_.length - 1 && buckets_[i].maxValue > buckets_[i + 1].minValue) {
                revert Errors.InvalidBuckets();
            }
            
            totalOdds += buckets_[i].oddsBps;
        }

        if (totalOdds != BASE_POINTS) revert Errors.InvalidBuckets();
    }
    
    function _validateBucketValues(BucketData memory bucket, uint256 packPrice) internal view {
        if (bucket.minValue == 0) revert Errors.InvalidReward();
        if (bucket.maxValue == 0) revert Errors.InvalidReward();
        if (bucket.minValue > bucket.maxValue) revert Errors.InvalidReward();
        if (bucket.minValue < minReward) revert Errors.InvalidReward();
        if (bucket.maxValue > maxReward) revert Errors.InvalidReward();
        
    }
    
    function _validateBucketOdds(BucketData memory bucket) internal pure {
        if (bucket.oddsBps == 0) revert Errors.InvalidBuckets();
        if (bucket.oddsBps > 10000) revert Errors.InvalidBuckets();
    }
    
    function _verifyPackSignature(
        PackType packType_,
        uint256 packPrice,
        BucketData[] memory buckets_,
        bytes memory signature_,
        address expectedCosigner
    ) internal view returns (bytes32) {
        bytes32 packHash = hashPack(packType_, packPrice, buckets_);
        address signer = verifyHash(packHash, signature_);
        
        if (signer != expectedCosigner) revert Errors.PackSignerMismatch();
        if (!isCosigner[signer]) revert Errors.PackSignerNotCosigner();
        
        return packHash;
    }
    
    function _createCommit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        uint256 packPrice,
        BucketData[] memory buckets_,
        bytes32 packHash
    ) internal returns (uint256) {
        uint256 commitId = packs.length;
        uint256 userCounter = packCount[receiver_]++;

        packs.push(CommitData({
            id: commitId,
            receiver: receiver_,
            cosigner: cosigner_,
            seed: seed_,
            counter: userCounter,
            packPrice: packPrice,
            buckets: buckets_,
            packHash: packHash
        }));
        
        return commitId;
    }
    
    function _processCommitFees(uint256 commitId, uint256 packPrice) internal {
        feesPaid[commitId] = msg.value - packPrice;
        protocolBalance += feesPaid[commitId];
        _handleFlatFeePayment();
        commitBalance += packPrice;
    }
    
    function _setCommitExpiryTimes(uint256 commitId) internal {
        commitCancellableAt[commitId] = block.timestamp + commitCancellableTime;
        commitUserCancellableAt[commitId] = block.timestamp + commitUserCancellableTime;
        nftFulfillmentExpiresAt[commitId] = block.timestamp + nftFulfillmentExpiryTime;
    }
    
    function _handleFlatFeePayment() internal {
        if (flatFee > 0 && fundsReceiver != address(0)) {
            (bool success, ) = fundsReceiver.call{value: flatFee}("");
            if (!success) {
                treasuryBalance += flatFee;
            }
        } else if (flatFee > 0) {
            treasuryBalance += flatFee;
        }
    }

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

    function _cancelByUser(uint256 commitId_) internal {
        _validateUserCancellationRequest(commitId_);

        isCancelled[commitId_] = true;
        CommitData memory commitData = packs[commitId_];
        uint256 totalRefund = _calculateAndUpdateRefund(commitId_, commitData.packPrice);
        _processRefund(commitId_, commitData.receiver, totalRefund, commitData);
        emit CommitCancelledByUser(commitId_, hashCommit(commitData));
    }
    
    function _validateCancellationRequest(uint256 commitId_) internal view {
        if (commitId_ >= packs.length) revert Errors.InvalidCommitId();
        if (isFulfilled[commitId_]) revert Errors.AlreadyFulfilled();
        if (isCancelled[commitId_]) revert Errors.CommitIsCancelled();
        if (block.timestamp < commitCancellableAt[commitId_]) {
            revert Errors.CommitNotCancellable();
        }
    }

    function _validateUserCancellationRequest(uint256 commitId_) internal view {
        if (commitId_ >= packs.length) revert Errors.InvalidCommitId();
        if (isFulfilled[commitId_]) revert Errors.AlreadyFulfilled();
        if (isCancelled[commitId_]) revert Errors.CommitIsCancelled();

        uint256 userCancellableAt = commitUserCancellableAt[commitId_];
    
        // Handle commits created before upgrade (legacy commits have 0 timestamp)
        // These are all internal. On the next major version this code can be removed.
        if (userCancellableAt == 0) {
            revert Errors.CommitUserCancellableTimeNotSet();
        }

        if (block.timestamp < commitUserCancellableAt[commitId_]) {
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
