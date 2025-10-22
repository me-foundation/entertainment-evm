// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PacksSignatureVerifierUpgradeable} from "../../common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";
import {IPRNG} from "../../common/interfaces/IPRNG.sol";

/* Do not remove any storage variables from this contract. Always add new variables to the end. */

/// @title PacksStorage
/// @notice Storage layout for Packs contract
/// @dev All storage variables and events for Packs
abstract contract PacksStorage is PacksSignatureVerifierUpgradeable {
    // ============================================================
    // STORAGE
    // ============================================================

    IPRNG public PRNG;
    address payable public fundsReceiver;

    CommitData[] public packs;
    mapping(bytes32 commitDigest => uint256 commitId) public commitIdByDigest;

    uint256 public treasuryBalance;
    uint256 public commitBalance;

    uint256 public constant MIN_COMMIT_CANCELLABLE_TIME = 1 minutes;
    uint256 public commitCancellableTime;
    mapping(uint256 commitId => uint256 cancellableAt) public commitCancellableAt;

    uint256 public constant MIN_NFT_FULFILLMENT_EXPIRY_TIME = 30 seconds;
    uint256 public nftFulfillmentExpiryTime;
    mapping(uint256 commitId => uint256 expiresAt) public nftFulfillmentExpiresAt;

    bytes32 public constant FUNDS_RECEIVER_MANAGER_ROLE = keccak256("FUNDS_RECEIVER_MANAGER_ROLE");

    mapping(address cosigner => bool active) public isCosigner;
    mapping(address receiver => uint256 counter) public packCount;
    mapping(uint256 commitId => bool fulfilled) public isFulfilled;
    mapping(uint256 commitId => bool cancelled) public isCancelled;

    uint256 public minReward;
    uint256 public maxReward;
    uint256 public minPackPrice;
    uint256 public maxPackPrice;

    uint256 public minPackRewardMultiplier; // deprecated. These slots are unused but have to remain here. 
    uint256 public maxPackRewardMultiplier; // deprecated. These slots are unused but have to remain here. 

    uint256 public constant MIN_BUCKETS = 1;
    uint256 public constant MAX_BUCKETS = 6;

    uint256 public constant BASE_POINTS = 10000;

    uint256 public protocolFee = 0;
    uint256 public protocolBalance = 0;
    mapping(uint256 commitId => uint256 protocolFee) public feesPaid;
    uint256 public flatFee = 0;
}

