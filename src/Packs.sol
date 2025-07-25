// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MEAccessControlUpgradeable} from "./common/MEAccessControlUpgradeable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";
import {TokenRescuer} from "./common/TokenRescuer.sol";

contract Packs is
    MEAccessControlUpgradeable,
    PausableUpgradeable,
    PacksSignatureVerifierUpgradeable,
    ReentrancyGuardUpgradeable,
    TokenRescuer
{
    IPRNG public PRNG;
    address payable public fundsReceiver;

    CommitData[] public packs;
    mapping(bytes32 commitDigest => uint256 commitId) public commitIdByDigest;

    uint256 public treasuryBalance; // The operational balance
    uint256 public commitBalance; // The open commit balance

    // Commits are cancellable after time passes unfulfilled
    uint256 public constant MIN_COMMIT_CANCELLABLE_TIME = 1 hours;
    uint256 public commitCancellableTime;
    mapping(uint256 commitId => uint256 cancellableAt) public commitCancellableAt;

    // NFT fulfillment option expires after a short time
    uint256 public constant MIN_NFT_FULFILLMENT_EXPIRY_TIME = 30 seconds;
    uint256 public nftFulfillmentExpiryTime;
    mapping(uint256 commitId => uint256 expiresAt) public nftFulfillmentExpiresAt;

    bytes32 public constant FUNDS_RECEIVER_MANAGER_ROLE = keccak256("FUNDS_RECEIVER_MANAGER_ROLE");

    mapping(address cosigner => bool active) public isCosigner;
    mapping(address receiver => uint256 counter) public packCount;
    mapping(uint256 commitId => bool fulfilled) public isFulfilled;
    mapping(uint256 commitId => bool cancelled) public isCancelled;

    uint256 public minReward; // Min ETH reward for a commit (whether it's NFT or payout)
    uint256 public maxReward; // Max ETH reward for a commit (whether it's NFT or payout)
    uint256 public minPackPrice; // Min ETH pack price for a commit
    uint256 public maxPackPrice; // Max ETH pack price for a commit

    uint256 public constant MIN_BUCKETS = 1;
    uint256 public constant MAX_BUCKETS = 5;

    uint256 public constant BASE_POINTS = 10000;

    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        uint256 packPrice,
        bytes32 packHash,
        bytes32 digest
    );
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
        address choiceSigner,
        FulfillmentOption choice,
        FulfillmentOption fulfillmentType,
        bytes32 digest
    );
    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);
    event MaxRewardUpdated(uint256 oldMaxReward, uint256 newMaxReward);
    event MaxPackPriceUpdated(uint256 oldMaxPackPrice, uint256 newMaxPackPrice);
    event TreasuryDeposit(address indexed sender, uint256 amount);
    event TreasuryWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    event EmergencyWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    event MinRewardUpdated(uint256 oldMinReward, uint256 newMinReward);
    event MinPackPriceUpdated(uint256 oldMinPackPrice, uint256 newMinPackPrice);
    event CommitCancellableTimeUpdated(uint256 oldCommitCancellableTime, uint256 newCommitCancellableTime);
    event NftFulfillmentExpiryTimeUpdated(uint256 oldNftFulfillmentExpiryTime, uint256 newNftFulfillmentExpiryTime);
    event CommitCancelled(uint256 indexed commitId, bytes32 digest);
    event FundsReceiverUpdated(address indexed oldFundsReceiver, address indexed newFundsReceiver);
    event FundsReceiverManagerTransferred(
        address indexed oldFundsReceiverManager, address indexed newFundsReceiverManager
    );
    event TransferFailure(uint256 indexed commitId, address indexed receiver, uint256 amount, bytes32 digest);

    error AlreadyCosigner();
    error AlreadyFulfilled();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidCommitOwner();
    error InvalidBuckets();
    error InvalidCosigner();
    error InvalidReceiver();
    error InvalidChoiceSigner();
    error InvalidReward();
    error InvalidPackPrice();
    error InvalidCommitId();
    error WithdrawalFailed();
    error InvalidCommitCancellableTime();
    error InvalidNftFulfillmentExpiryTime();
    error CommitIsCancelled();
    error CommitNotCancellable();
    error InvalidFundsReceiver();
    error InvalidFundsReceiverManager();
    error InitialOwnerCannotBeZero();
    error BucketSelectionFailed();
    error InvalidMarketplace();
    error InvalidPayoutAmount();
    error InvalidOrderAmount();
    error PayoutAmountGreaterThanOrderAmount();

    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (packs[commitId_].receiver != msg.sender && packs[commitId_].cosigner != msg.sender) {
            revert InvalidCommitOwner();
        }
        _;
    }

    constructor(
        address fundsReceiver_,
        address prng_,
        address fundsReceiverManager_
    ) initializer {
        __MEAccessControl_init();
        __Pausable_init();
        __PacksSignatureVerifier_init("Packs", "1");
        __ReentrancyGuard_init();

        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setFundsReceiver(fundsReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FUNDS_RECEIVER_MANAGER_ROLE, fundsReceiverManager_);

        // Initialize reward limits
        minReward = 0.01 ether;
        maxReward = 5 ether;

        minPackPrice = 0.01 ether;
        maxPackPrice = 0.25 ether;

        // Initialize expiries
        commitCancellableTime = 1 days;
        nftFulfillmentExpiryTime = 10 minutes;
    }

    /// @notice Allows a user to commit funds for a pack purchase
    /// @param receiver_ Address that will receive the NFT/ETH if won
    /// @param cosigner_ Address of the authorized cosigner
    /// @param seed_ Random seed for the commit
    /// @param packType_ Type of pack
    /// @param buckets_ Buckets used in the pack
    /// @param signature_ Signature is the cosigned hash of packPrice + buckets[]
    /// @dev Emits a Commit event on success
    /// @return commitId The ID of the created commit
    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        PackType packType_,
        BucketData[] memory buckets_,
        bytes memory signature_
    ) public payable whenNotPaused returns (uint256) {
        // Amount user is sending to purchase the pack
        uint256 packPrice = msg.value;

        if (packPrice == 0) revert InvalidAmount();
        if (packPrice < minPackPrice) revert InvalidAmount();
        if (packPrice > maxPackPrice) revert InvalidAmount();

        if (!isCosigner[cosigner_]) revert InvalidCosigner();
        if (cosigner_ == address(0)) revert InvalidCosigner();
        if (receiver_ == address(0)) revert InvalidReceiver();

        // Validate bucket count
        if (buckets_.length < MIN_BUCKETS) revert InvalidBuckets();
        if (buckets_.length > MAX_BUCKETS) revert InvalidBuckets();

        // Validate bucket's min and max values, ascending value range, and odds
        uint256 totalOdds = 0;
        for (uint256 i = 0; i < buckets_.length; i++) {
            if (buckets_[i].minValue == 0) revert InvalidReward();
            if (buckets_[i].maxValue == 0) revert InvalidReward();
            if (buckets_[i].minValue > buckets_[i].maxValue) revert InvalidReward();
            if (buckets_[i].minValue < minReward) revert InvalidReward();
            if (buckets_[i].maxValue > maxReward) revert InvalidReward();
            if (buckets_[i].oddsBps == 0) revert InvalidBuckets();
            if (buckets_[i].oddsBps > BASE_POINTS) revert InvalidBuckets();
            if (i < buckets_.length - 1 && buckets_[i].maxValue >= buckets_[i + 1].minValue) revert InvalidBuckets();

            // Sum individual probabilities
            totalOdds += buckets_[i].oddsBps;
        }

        // Final total odds check - must equal 10000 (100%)
        if (totalOdds != BASE_POINTS) revert InvalidBuckets();

        // Hash pack for cosigner validation and event emission
        // Pack data gets re-checked in commitSignature on fulfill
        bytes32 packHash = hashPack(packType_, packPrice, buckets_);
        address cosigner = verifyHash(packHash, signature_);
        if (cosigner != cosigner_) revert InvalidCosigner();
        if (!isCosigner[cosigner]) revert InvalidCosigner();

        uint256 commitId = packs.length;
        uint256 userCounter = packCount[receiver_]++;

        commitBalance += packPrice;

        CommitData memory commitData = CommitData({
            id: commitId,
            receiver: receiver_,
            cosigner: cosigner_,
            seed: seed_,
            counter: userCounter,
            packPrice: packPrice,
            buckets: buckets_,
            packHash: packHash
        });

        packs.push(commitData);
        commitCancellableAt[commitId] = block.timestamp + commitCancellableTime;
        nftFulfillmentExpiresAt[commitId] = block.timestamp + nftFulfillmentExpiryTime;

        bytes32 digest = hashCommit(commitData);
        commitIdByDigest[digest] = commitId;

        emit Commit(msg.sender, commitId, receiver_, cosigner_, seed_, userCounter, packPrice, packHash, digest);

        return commitId;
    }

    /// @notice Get the index of the bucket selected for a given RNG value
    /// @param rng RNG value (0-10000)
    /// @param buckets Array of bucket data
    /// @return bucketIndex_ Index of the selected bucket
    function _getBucketIndex(uint256 rng, BucketData[] memory buckets) internal pure returns (uint256 bucketIndex_) {
        uint256 cumulativeOdds = 0;
        for (uint256 i = 0; i < buckets.length; i++) {
            cumulativeOdds += buckets[i].oddsBps;
            if (rng < cumulativeOdds) {
                return i;
            }
        }
        revert BucketSelectionFailed();
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitId_ ID of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param payoutAmount_ Amount of ETH to send to the receiver on payout choice
    /// @param commitSignature_ Signature used for commit data
    /// @param fulfillmentSignature_ Signature used for orderData (and to validate orderData)
    /// @param choice_ Choice made by the receiver (Payout = 0, NFT = 1)
    /// @param choiceSignature_ Signature used for receiver's choice (only required for NFT choice)
    /// @dev Emits a Fulfillment event on success
    function fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        bytes calldata commitSignature_,
        bytes calldata fulfillmentSignature_,
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) public payable whenNotPaused {
        _fulfill(
            commitId_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            payoutAmount_,
            commitSignature_,
            fulfillmentSignature_,
            choice_,
            choiceSignature_
        );
    }

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
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) internal nonReentrant {
        // Basic validation of tx
        if (marketplace_ == address(0)) revert InvalidMarketplace();
        if (msg.value > 0) _depositTreasury(msg.value);
        if (orderAmount_ > treasuryBalance) revert InsufficientBalance();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isCancelled[commitId_]) revert CommitIsCancelled();
        if (commitId_ >= packs.length) revert InvalidCommitId();
        if (payoutAmount_ > orderAmount_) revert PayoutAmountGreaterThanOrderAmount();

        CommitData memory commitData = packs[commitId_];

        // Check the cosigner signed the commit
        address commitCosigner = verifyCommit(commitData, commitSignature_);
        if (commitCosigner != commitData.cosigner) revert InvalidCosigner();
        if (!isCosigner[commitCosigner]) revert InvalidCosigner();

        uint256 rng = PRNG.rng(commitSignature_);
        bytes32 digest = hashCommit(commitData);
        bytes32 fulfillmentHash =
            hashFulfillment(digest, marketplace_, orderAmount_, orderData_, token_, tokenId_, payoutAmount_, choice_);

        // Check the cosigner signed the order data
        address fulfillmentCosigner = verifyHash(fulfillmentHash, fulfillmentSignature_);
        if (fulfillmentCosigner != commitData.cosigner) revert InvalidCosigner();
        if (!isCosigner[fulfillmentCosigner]) revert InvalidCosigner();

        // Determine bucket and validate orderAmount and payoutAmount are within bucket range
        uint256 bucketIndex = _getBucketIndex(rng, commitData.buckets);
        BucketData memory bucket = commitData.buckets[bucketIndex];
        if (orderAmount_ < bucket.minValue) revert InvalidOrderAmount();
        if (orderAmount_ > bucket.maxValue) revert InvalidOrderAmount();
        if (payoutAmount_ < bucket.minValue) revert InvalidPayoutAmount();
        if (payoutAmount_ > bucket.maxValue) revert InvalidPayoutAmount();

        // Check the fulfillment option
        address choiceSigner = verifyHash(fulfillmentHash, choiceSignature_);
        if (choiceSigner != commitData.receiver && choiceSigner != commitData.cosigner) revert InvalidChoiceSigner();

        // If the user wants to fulfill via NFT but the option has expired, default to payout
        FulfillmentOption fulfillmentType = choice_;
        if (choice_ == FulfillmentOption.NFT && block.timestamp > nftFulfillmentExpiresAt[commitId_]) {
            fulfillmentType = FulfillmentOption.Payout;
        }

        // Mark the commit as fulfilled
        isFulfilled[commitId_] = true;

        // Forward pack revenue to the funds receiver
        commitBalance -= commitData.packPrice;
        (bool revenueSuccess,) = payable(fundsReceiver).call{value: commitData.packPrice}("");
        if (!revenueSuccess) {
            // If the transfer fails, fall back to treasury so the admin can rescue later
            treasuryBalance += commitData.packPrice;
        }

        // Handle user choice and fulfil order or payout
        if (fulfillmentType == FulfillmentOption.NFT) {
            // execute the market data to transfer the nft
            bool success = _fulfillOrder(marketplace_, orderData_, orderAmount_);
            if (success) {
                // subtract the order amount from the treasury balance
                treasuryBalance -= orderAmount_;
                // emit a success transfer for the nft
                emit Fulfillment(
                    msg.sender,
                    commitId_,
                    rng,
                    bucket.oddsBps,
                    bucketIndex,
                    0, // payout is 0 ETH for NFT fulfillment
                    token_,
                    tokenId_,
                    orderAmount_,
                    commitData.receiver,
                    choiceSigner,
                    choice_,
                    fulfillmentType,
                    digest
                );
            } else {
                // The order failed to fulfill, it could be bought already or invalid, make the best effort to send the user the value of the order they won.
                (bool fallbackSuccess,) = commitData.receiver.call{value: orderAmount_}("");
                if (fallbackSuccess) {
                    treasuryBalance -= orderAmount_;
                } else {
                    emit TransferFailure(commitData.id, commitData.receiver, orderAmount_, digest);
                }
                // emit the failure (they wanted the NFT but got the NFT value as a payout)
                emit Fulfillment(
                    msg.sender,
                    commitId_,
                    rng,
                    bucket.oddsBps,
                    bucketIndex,
                    orderAmount_, // payout amount when NFT fails (full order amount)
                    address(0), // no NFT token address when NFT fails
                    0, // no NFT token ID when NFT fails
                    0, // no NFT amount when NFT fails
                    commitData.receiver,
                    choiceSigner,
                    choice_,
                    fulfillmentType,
                    digest
                );
            }
        } else {
            // Payout fulfillment route
            // Calculate payout remainder to fundsReceiver
            uint256 remainderAmount = orderAmount_ - payoutAmount_;

            (bool success,) = commitData.receiver.call{value: payoutAmount_}("");
            if (success) {
                treasuryBalance -= payoutAmount_;
            } else {
                emit TransferFailure(commitData.id, commitData.receiver, payoutAmount_, digest);
            }

            // Transfer the remainder to the funds receiver
            if (remainderAmount > 0) {
                (bool remainderSuccess,) = payable(fundsReceiver).call{value: remainderAmount}("");
                if (remainderSuccess) {
                    treasuryBalance -= remainderAmount;
                }
                // If transfer fails, keep funds in the treasury for later rescue
            }

            // emit the payout
            emit Fulfillment(
                msg.sender,
                commitId_,
                rng,
                bucket.oddsBps,
                bucketIndex,
                payoutAmount_,
                address(0), // no NFT token address for payout
                0, // no NFT token ID for payout
                0, // no NFT amount for payout
                commitData.receiver,
                choiceSigner,
                choice_,
                fulfillmentType,
                digest
            );
        }
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitDigest_ Digest of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param payoutAmount_ Amount of ETH to send to the receiver on payout choice
    /// @param commitSignature_ Signature used for commit data
    /// @param fulfillmentSignature_ Signature used for fulfillment data
    /// @param choice_ Choice made by the receiver
    /// @param choiceSignature_ Signature used for receiver's choice
    /// @dev Emits a Fulfillment event on success
    function fulfillByDigest(
        bytes32 commitDigest_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        uint256 payoutAmount_,
        bytes calldata commitSignature_,
        bytes calldata fulfillmentSignature_,
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) public payable whenNotPaused {
        return fulfill(
            commitIdByDigest[commitDigest_],
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            payoutAmount_,
            commitSignature_,
            fulfillmentSignature_,
            choice_,
            choiceSignature_
        );
    }

    /// @notice Allows the admin to withdraw ETH from the treasury balance
    /// @param amount The amount of ETH to withdraw
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function withdrawTreasury(uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > treasuryBalance) revert InsufficientBalance();
        treasuryBalance -= amount;

        (bool success,) = payable(fundsReceiver).call{value: amount}("");
        if (!success) revert WithdrawalFailed();

        emit TreasuryWithdrawal(msg.sender, amount, fundsReceiver);
    }

    /// @notice Allows the admin to withdraw all ETH from the contract
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function emergencyWithdraw() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryBalance = 0;
        commitBalance = 0;

        uint256 currentBalance = address(this).balance;

        _rescueETH(fundsReceiver, currentBalance);

        _pause();
        emit EmergencyWithdrawal(msg.sender, currentBalance, fundsReceiver);
    }

    /// @notice Allows the receiver or cosigner to cancel a commit in the event that the commit is not or cannot be fulfilled
    /// @param commitId_ ID of the commit to cancel
    /// @dev Only callable by the receiver or cosigner
    /// @dev It's safe to allow receiver to call cancel as the commit should be fulfilled within commitCancellableTime
    /// @dev If not fulfilled before commitCancellableTime, it indicates a fulfillment issue so commit should be refunded
    /// @dev Emits a CommitCancelled event
    function cancel(uint256 commitId_) external onlyCommitOwnerOrCosigner(commitId_) nonReentrant {
        if (commitId_ >= packs.length) revert InvalidCommitId();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isCancelled[commitId_]) revert CommitIsCancelled();
        if (block.timestamp < commitCancellableAt[commitId_]) {
            revert CommitNotCancellable();
        }

        isCancelled[commitId_] = true;

        CommitData memory commitData = packs[commitId_];

        uint256 commitAmount = commitData.packPrice;
        commitBalance -= commitAmount;

        (bool success,) = payable(commitData.receiver).call{value: commitAmount}("");
        if (!success) {
            // If the transfer fails, fall back to treasury so the admin can rescue later
            treasuryBalance += commitAmount;
            emit TransferFailure(commitId_, commitData.receiver, commitAmount, hashCommit(commitData));
        }

        emit CommitCancelled(commitId_, hashCommit(commitData));
    }

    // ############################################################
    // ############ RESCUE FUNCTIONS ############
    // ############################################################

    function rescueERC20(address token, address to, uint256 amount) external onlyRole(RESCUE_ROLE) {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        amounts[0] = amount;

        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721(address token, address to, uint256 tokenId) external onlyRole(RESCUE_ROLE) {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;

        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155(address token, address to, uint256 tokenId, uint256 amount) external onlyRole(RESCUE_ROLE) {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;
        amounts[0] = amount;

        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }

    function rescueERC20Batch(address[] calldata tokens, address[] calldata tos, uint256[] calldata amounts)
        external
        onlyRole(RESCUE_ROLE)
    {
        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721Batch(address[] calldata tokens, address[] calldata tos, uint256[] calldata tokenIds)
        external
        onlyRole(RESCUE_ROLE)
    {
        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyRole(RESCUE_ROLE) {
        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }

    // ############################################################
    // ############ GETTERS & SETTERS ############
    // ############################################################

    /// @notice Adds a new authorized cosigner
    /// @param cosigner_ Address to add as cosigner
    /// @dev Only callable by admin role
    /// @dev Emits a CoSignerAdded event
    function addCosigner(address cosigner_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (cosigner_ == address(0)) revert InvalidCosigner();
        if (isCosigner[cosigner_]) revert AlreadyCosigner();
        isCosigner[cosigner_] = true;
        emit CosignerAdded(cosigner_);
    }

    /// @notice Removes an authorized cosigner
    /// @param cosigner_ Address to remove as cosigner
    /// @dev Only callable by admin role
    /// @dev Emits a CoSignerRemoved event
    function removeCosigner(address cosigner_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isCosigner[cosigner_]) revert InvalidCosigner();
        isCosigner[cosigner_] = false;
        emit CosignerRemoved(cosigner_);
    }

    /// @notice Sets the commit cancellable time.
    /// @param commitCancellableTime_ New commit cancellable time
    /// @dev Only callable by admin role
    /// @dev Emits a CommitCancellableTimeUpdated event
    function setCommitCancellableTime(uint256 commitCancellableTime_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (commitCancellableTime_ < MIN_COMMIT_CANCELLABLE_TIME) {
            revert InvalidCommitCancellableTime();
        }
        uint256 oldCommitCancellableTime = commitCancellableTime;
        commitCancellableTime = commitCancellableTime_;
        emit CommitCancellableTimeUpdated(oldCommitCancellableTime, commitCancellableTime_);
    }

    /// @notice Sets the NFT fulfillment expiry time
    /// @param nftFulfillmentExpiryTime_ New NFT fulfillment expiry time
    /// @dev Only callable by admin role
    /// @dev Emits a NftFulfillmentExpiryTimeUpdated event
    function setNftFulfillmentExpiryTime(uint256 nftFulfillmentExpiryTime_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (nftFulfillmentExpiryTime_ < MIN_NFT_FULFILLMENT_EXPIRY_TIME) {
            revert InvalidNftFulfillmentExpiryTime();
        }
        uint256 oldNftFulfillmentExpiryTime = nftFulfillmentExpiryTime;
        nftFulfillmentExpiryTime = nftFulfillmentExpiryTime_;
        emit NftFulfillmentExpiryTimeUpdated(oldNftFulfillmentExpiryTime, nftFulfillmentExpiryTime_);
    }

    /// @notice Sets the maximum allowed reward
    /// @param maxReward_ New maximum reward value
    /// @dev Only callable by admin role
    function setMaxReward(uint256 maxReward_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxReward_ < minReward) revert InvalidReward();

        uint256 oldMaxReward = maxReward;
        maxReward = maxReward_;
        emit MaxRewardUpdated(oldMaxReward, maxReward_);
    }

    /// @notice Sets the minimum allowed reward
    /// @param minReward_ New minimum reward value
    /// @dev Only callable by admin role
    function setMinReward(uint256 minReward_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minReward_ > maxReward) revert InvalidReward();

        uint256 oldMinReward = minReward;
        minReward = minReward_;
        emit MinRewardUpdated(oldMinReward, minReward_);
    }

    /// @notice Sets the minimum pack price
    /// @param minPackPrice_ New minimum pack price
    /// @dev Only callable by admin role
    /// @dev Emits a MinPackPriceUpdated event
    function setMinPackPrice(uint256 minPackPrice_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minPackPrice_ > maxPackPrice) revert InvalidPackPrice();

        uint256 oldMinPackPrice = minPackPrice;
        minPackPrice = minPackPrice_;
        emit MinPackPriceUpdated(oldMinPackPrice, minPackPrice_);
    }

    /// @notice Sets the maximum pack price
    /// @param maxPackPrice_ New maximum pack price
    /// @dev Only callable by admin role
    /// @dev Emits a MaxPackPriceUpdated event
    function setMaxPackPrice(uint256 maxPackPrice_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxPackPrice_ < minPackPrice) revert InvalidPackPrice();

        uint256 oldMaxPackPrice = maxPackPrice;
        maxPackPrice = maxPackPrice_;
        emit MaxPackPriceUpdated(oldMaxPackPrice, maxPackPrice_);
    }

    /// @notice Deposits ETH into the treasury
    /// @dev Called internally when receiving ETH
    /// @param amount Amount of ETH to deposit
    function _depositTreasury(uint256 amount) internal {
        treasuryBalance += amount;
        emit TreasuryDeposit(msg.sender, amount);
    }

    /// @notice Pauses the contract
    /// @dev Only callable by admin role
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Handles receiving ETH
    /// @dev Required for contract to receive ETH
    receive() external payable {
        _depositTreasury(msg.value);
    }

    /// @notice Handles receiving ERC1155 tokens
    /// @dev Required for contract to receive ERC1155 tokens
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /// @notice Handles receiving batch ERC1155 tokens
    /// @dev Required for contract to receive batch ERC1155 tokens
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice Handles receiving ERC721 tokens
    /// @dev Required for contract to receive ERC721 tokens via safeTransferFrom
    function onERC721Received() external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Fulfills an order with the specified parameters
    /// @dev Internal function called by fulfill()
    /// @param to Address to send the transaction to
    /// @param data Calldata for the transaction
    /// @param amount Amount of ETH to send
    /// @return success Whether the transaction was successful
    function _fulfillOrder(address to, bytes calldata data, uint256 amount) internal returns (bool success) {
        (success,) = to.call{value: amount}(data);
    }

    /// @notice Transfers the funds receiver manager role
    /// @param newFundsReceiverManager_ New funds receiver manager
    /// @dev Only callable by funds receiver manager role
    function transferFundsReceiverManager(address newFundsReceiverManager_)
        external
        onlyRole(FUNDS_RECEIVER_MANAGER_ROLE)
    {
        if (newFundsReceiverManager_ == address(0)) {
            revert InvalidFundsReceiverManager();
        }
        _transferFundsReceiverManager(newFundsReceiverManager_);
    }

    /// @notice Transfers the funds receiver manager role
    /// @param newFundsReceiverManager_ New funds receiver manager
    function _transferFundsReceiverManager(address newFundsReceiverManager_) internal {
        _revokeRole(FUNDS_RECEIVER_MANAGER_ROLE, msg.sender);
        _grantRole(FUNDS_RECEIVER_MANAGER_ROLE, newFundsReceiverManager_);
        emit FundsReceiverManagerTransferred(msg.sender, newFundsReceiverManager_);
    }

    /// @notice Sets the funds receiver
    /// @param fundsReceiver_ Address to set as funds receiver
    /// @dev Only callable by funds receiver manager role
    function setFundsReceiver(address fundsReceiver_) external onlyRole(FUNDS_RECEIVER_MANAGER_ROLE) {
        _setFundsReceiver(fundsReceiver_);
    }

    /// @notice Sets the funds receiver
    /// @param fundsReceiver_ Address to set as funds receiver
    function _setFundsReceiver(address fundsReceiver_) internal {
        if (fundsReceiver_ == address(0)) revert InvalidFundsReceiver();
        if (hasRole(FUNDS_RECEIVER_MANAGER_ROLE, fundsReceiver_)) {
            revert InvalidFundsReceiverManager();
        }
        address oldFundsReceiver = fundsReceiver;
        fundsReceiver = payable(fundsReceiver_);
        emit FundsReceiverUpdated(oldFundsReceiver, fundsReceiver_);
    }
}
