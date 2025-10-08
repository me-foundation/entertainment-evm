// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PacksStorage.sol";
import {Errors} from "../../common/Errors.sol";

/// @title PacksFulfill
/// @notice Handles fulfillment flow logic for Packs contract
/// @dev Abstract contract with fulfillment helpers - storage accessed from PacksStorage
abstract contract PacksFulfill is PacksStorage {
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event Fulfillment(
        address indexed sender,
        uint256 indexed commitId,
        uint256 rng,
        uint256 odds,
        uint256 bucketIndex,
        uint256 payout,
        address token,
        uint256 tokenId,
        uint256 amount,
        address receiver,
        FulfillmentOption choice,
        FulfillmentOption fulfillmentType,
        bytes32 digest
    );
    
    event FulfillmentPayoutFailed(uint256 indexed commitId, address indexed receiver, uint256 amount, bytes32 digest);
    event TreasuryDeposit(address indexed sender, uint256 amount);
    
    // ============================================================
    // FULFILLMENT LOGIC
    // ============================================================
    
    function _fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        bytes calldata commitSignature_,
        bytes calldata fulfillmentSignature_,
        FulfillmentOption choice_
    ) internal {
        CommitData memory commitData = _validateFulfillmentRequest(commitId_, marketplace_, orderAmount_, payoutAmount_);
        (uint256 rng, bytes32 digest) = _verifyFulfillmentSignatures(
            commitData, commitSignature_, fulfillmentSignature_, marketplace_,
            orderData_, orderAmount_, token_, tokenId_, payoutAmount_, choice_
        );
        (uint256 bucketIndex, BucketData memory bucket) = _determineOutcomeAndValidate(
            rng, commitData.buckets, orderAmount_, payoutAmount_
        );
        FulfillmentOption fulfillmentType = _determineFulfillmentType(commitId_, choice_);
        _markFulfilledAndUpdateBalances(commitId_, commitData.packPrice);
        _executeFulfillment(
            commitId_, commitData, marketplace_, orderData_, orderAmount_,
            token_, tokenId_, payoutAmount_, rng, bucket, bucketIndex,
            choice_, fulfillmentType, digest
        );
    }
    
    function _validateFulfillmentRequest(
        uint256 commitId_,
        address marketplace_,
        uint256 orderAmount_,
        uint256 payoutAmount_
    ) internal returns (CommitData memory) {
        if (commitId_ >= packs.length) revert Errors.InvalidCommitId();
        if (msg.sender != packs[commitId_].cosigner) revert Errors.OnlyCosignerCanFulfill();
        if (marketplace_ == address(0)) revert Errors.MarketplaceAddressZero();
        if (msg.value > 0) _depositTreasury(msg.value);
        if (orderAmount_ > treasuryBalance) revert Errors.InsufficientTreasuryBalance();
        if (isFulfilled[commitId_]) revert Errors.AlreadyFulfilled();
        if (isCancelled[commitId_]) revert Errors.CommitIsCancelled();
        if (payoutAmount_ > orderAmount_) revert Errors.PayoutExceedsOrderAmount();

        return packs[commitId_];
    }
    
    function _verifyFulfillmentSignatures(
        CommitData memory commitData,
        bytes calldata commitSignature_,
        bytes calldata fulfillmentSignature_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        FulfillmentOption choice_
    ) internal view returns (uint256 rng, bytes32 digest) {
        address commitCosigner = verifyCommit(commitData, commitSignature_);
        if (commitCosigner != commitData.cosigner) revert Errors.CommitSignerMismatch();
        if (!isCosigner[commitCosigner]) revert Errors.CommitSignerNotCosigner();

        rng = PRNG.rng(commitSignature_);
        digest = hashCommit(commitData);

        bytes32 fulfillmentHash = hashFulfillment(
            digest, marketplace_, orderAmount_, orderData_, 
            token_, tokenId_, payoutAmount_, choice_
        );
        address fulfillmentCosigner = verifyHash(fulfillmentHash, fulfillmentSignature_);
        if (fulfillmentCosigner != commitData.cosigner) revert Errors.FulfillmentSignerMismatch();
        if (!isCosigner[fulfillmentCosigner]) revert Errors.FulfillmentSignerNotCosigner();
    }
    
    function _determineOutcomeAndValidate(
        uint256 rng,
        BucketData[] memory buckets,
        uint256 orderAmount_,
        uint256 payoutAmount_
    ) internal pure returns (uint256 bucketIndex, BucketData memory bucket) {
        bucketIndex = _getBucketIndex(rng, buckets);
        bucket = buckets[bucketIndex];
        
        if (orderAmount_ < bucket.minValue) revert Errors.OrderAmountBelowBucketMin();
        if (orderAmount_ > bucket.maxValue) revert Errors.OrderAmountAboveBucketMax();
        if (payoutAmount_ < bucket.minValue) revert Errors.PayoutAmountBelowBucketMin();
        if (payoutAmount_ > bucket.maxValue) revert Errors.PayoutAmountAboveBucketMax();
    }
    
    function _getBucketIndex(uint256 rng, BucketData[] memory buckets) internal pure returns (uint256) {
        uint256 cumulativeOdds = 0;
        for (uint256 i = 0; i < buckets.length; i++) {
            cumulativeOdds += buckets[i].oddsBps;
            if (rng < cumulativeOdds) {
                return i;
            }
        }
        revert Errors.BucketSelectionFailed();
    }
    
    function _determineFulfillmentType(uint256 commitId_, FulfillmentOption choice_) internal view returns (FulfillmentOption) {
        if (choice_ == FulfillmentOption.NFT && block.timestamp > nftFulfillmentExpiresAt[commitId_]) {
            return FulfillmentOption.Payout;
        }
        return choice_;
    }
    
    function _markFulfilledAndUpdateBalances(uint256 commitId_, uint256 packPrice) internal {
        isFulfilled[commitId_] = true;
        commitBalance -= packPrice;
        treasuryBalance += packPrice;
        uint256 protocolFeesPaid = feesPaid[commitId_];
        protocolBalance -= protocolFeesPaid;
        treasuryBalance += protocolFeesPaid;
    }
    
    function _executeFulfillment(
        uint256 commitId_,
        CommitData memory commitData,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        uint256 rng,
        BucketData memory bucket,
        uint256 bucketIndex,
        FulfillmentOption choice_,
        FulfillmentOption fulfillmentType,
        bytes32 digest
    ) internal {
        if (fulfillmentType == FulfillmentOption.NFT) {
            _executeNFTFulfillment(commitId_, commitData, marketplace_, orderData_, orderAmount_,
                token_, tokenId_, rng, bucket, bucketIndex, choice_, fulfillmentType, digest);
        } else {
            _executePayoutFulfillment(commitId_, commitData, payoutAmount_, rng, bucket,
                bucketIndex, choice_, fulfillmentType, digest);
        }
    }
    
    function _executeNFTFulfillment(
        uint256 commitId_,
        CommitData memory commitData,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 rng,
        BucketData memory bucket,
        uint256 bucketIndex,
        FulfillmentOption choice_,
        FulfillmentOption fulfillmentType,
        bytes32 digest
    ) internal {
        bool success = _tryFulfillNFTOrder(marketplace_, orderData_, orderAmount_);
        
        if (success) {
            treasuryBalance -= orderAmount_;
            emit Fulfillment(msg.sender, commitId_, rng, bucket.oddsBps, bucketIndex,
                0, token_, tokenId_, orderAmount_, commitData.receiver, choice_, fulfillmentType, digest);
        } else {
            (bool fallbackSuccess,) = commitData.receiver.call{value: orderAmount_}("");
            if (fallbackSuccess) {
                treasuryBalance -= orderAmount_;
            } else {
                emit FulfillmentPayoutFailed(commitData.id, commitData.receiver, orderAmount_, digest);
            }
            emit Fulfillment(msg.sender, commitId_, rng, bucket.oddsBps, bucketIndex,
                orderAmount_, address(0), 0, 0, commitData.receiver, choice_, fulfillmentType, digest);
        }
    }
    
    function _tryFulfillNFTOrder(address marketplace_, bytes calldata orderData_, uint256 orderAmount_) internal returns (bool) {
        try this._fulfillOrder(marketplace_, orderData_, orderAmount_) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
    
    function _executePayoutFulfillment(
        uint256 commitId_,
        CommitData memory commitData,
        uint256 payoutAmount_,
        uint256 rng,
        BucketData memory bucket,
        uint256 bucketIndex,
        FulfillmentOption choice_,
        FulfillmentOption fulfillmentType,
        bytes32 digest
    ) internal {
        (bool success,) = commitData.receiver.call{value: payoutAmount_}("");
        if (success) {
            treasuryBalance -= payoutAmount_;
        } else {
            emit FulfillmentPayoutFailed(commitData.id, commitData.receiver, payoutAmount_, digest);
        }

        emit Fulfillment(msg.sender, commitId_, rng, bucket.oddsBps, bucketIndex,
            payoutAmount_, address(0), 0, 0, commitData.receiver, choice_, fulfillmentType, digest);
    }
    
    function _fulfillOrder(address to, bytes calldata data, uint256 amount) public virtual returns (bool success) {
        (success,) = to.call{value: amount}(data);
    }
    
    function _depositTreasury(uint256 amount) internal {
        treasuryBalance += amount;
        emit TreasuryDeposit(msg.sender, amount);
    }
}
