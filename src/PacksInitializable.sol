// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MEAccessControlUpgradeable} from "./common/MEAccessControlUpgradeable.sol";
import {PacksSignatureVerifierUpgradeable} from "./common/PacksSignatureVerifierUpgradeable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";
import {TokenRescuer} from "./common/TokenRescuer.sol";

contract PacksInitializable is
    MEAccessControlUpgradeable,
    PausableUpgradeable,
    PacksSignatureVerifierUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    TokenRescuer
{
    IPRNG public PRNG;
    address payable public feeReceiver;

    CommitData[] public packs;
    mapping(bytes32 commitDigest => uint256 commitId) public commitIdByDigest;

    uint256 public treasuryBalance; // The contract balance
    uint256 public commitBalance; // The open commit balances

    // Commits are cancellable after time passes unfulfilled
    uint256 public constant MIN_COMMIT_CANCELLABLE_TIME = 1 minutes;
    uint256 public commitCancellableTime = 10 minutes;
    mapping(uint256 commitId => uint256 cancellableAt) public commitCancellableAt;

    // NFT fulfillment option expires after a short time
    uint256 public constant MIN_NFT_FULFILLMENT_EXPIRY_TIME = 30 seconds;
    uint256 public nftFulfillmentExpiryTime = 1 minutes;
    mapping(uint256 commitId => uint256 expiresAt) public nftFulfillmentExpiresAt;

    bytes32 public constant FEE_RECEIVER_MANAGER_ROLE = keccak256("FEE_RECEIVER_MANAGER_ROLE");

    mapping(address cosigner => bool active) public isCosigner;
    mapping(address receiver => uint256 counter) public packCount;
    mapping(uint256 commitId => bool fulfilled) public isFulfilled;
    mapping(uint256 commitId => bool cancelled) public isCancelled;

    uint256 public payoutBps; // When user selects payout as reward
    uint256 public minReward; // Min ETH reward for a commit (whether it's NFT or payout)
    uint256 public maxReward; // Max ETH reward for a commit (whether it's NFT or payout)
    uint256 public minPackPrice; // Min ETH pack price for a commit
    uint256 public maxPackPrice; // Max ETH pack price for a commit

    // Storage gap for future upgrades
    uint256[50] private __gap;

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
    event Withdrawal(address indexed sender, uint256 amount, address feeReceiver);
    event Deposit(address indexed sender, uint256 amount);
    event MinRewardUpdated(uint256 oldMinReward, uint256 newMinReward);
    event MinPackPriceUpdated(uint256 oldMinPackPrice, uint256 newMinPackPrice);
    event CommitCancellableTimeUpdated(uint256 oldCommitCancellableTime, uint256 newCommitCancellableTime);
    event NftFulfillmentExpiryTimeUpdated(uint256 oldNftFulfillmentExpiryTime, uint256 newNftFulfillmentExpiryTime);
    event CommitCancelled(uint256 indexed commitId, bytes32 digest);
    event PayoutBpsUpdated(uint256 oldPayoutBps, uint256 newPayoutBps);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event FeeReceiverManagerTransferred(address indexed oldFeeReceiverManager, address indexed newFeeReceiverManager);
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
    error InvalidPayoutBps();
    error InvalidFeeReceiver();
    error InvalidFeeReceiverManager();
    error InitialOwnerCannotBeZero();
    error NewImplementationCannotBeZero();
    error BucketSelectionFailed();
    error InvalidFulfillmentOption();
    error InvalidRng();

    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (packs[commitId_].receiver != msg.sender && packs[commitId_].cosigner != msg.sender) {
            revert InvalidCommitOwner();
        }
        _;
    }

    /// @dev Disables initializers for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and handles any pre-existing balance
    /// @dev Sets up EIP712 domain separator and deposits any ETH sent during deployment
    function initialize(address initialOwner_, address feeReceiver_, address prng_, address feeReceiverManager_)
        public
        initializer
    {
        if (initialOwner_ == address(0)) revert InitialOwnerCannotBeZero();

        __MEAccessControl_init(initialOwner_);
        __Pausable_init();
        __PacksSignatureVerifier_init("Packs", "1");
        __ReentrancyGuard_init();

        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setFeeReceiver(feeReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);

        // Initialize reward limits
        payoutBps = 9000;
        minReward = 0.01 ether;
        maxReward = 5 ether;

        minPackPrice = 0.01 ether;
        maxPackPrice = 0.25 ether;
    }

    /// @dev Overriden to prevent unauthorized upgrades.
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert NewImplementationCannotBeZero();
    }

    /// @notice Allows a user to commit funds for a pack purchase
    /// @param receiver_ Address that will receive the NFT/ETH if won
    /// @param cosigner_ Address of the authorized cosigner
    /// @param seed_ Random seed for the commit
    /// @param buckets_ Buckets used in the pack
    /// @param signature_ Signature is the cosigned hash of packPrice + buckets[]
    /// @dev Emits a Commit event on success
    /// @return commitId The ID of the created commit
    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
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
        if (buckets_.length == 0) revert InvalidBuckets();
        if (buckets_.length > 5) revert InvalidBuckets();

        // Validate bucket's min and max values
        for (uint256 i = 0; i < buckets_.length; i++) {
            if (buckets_[i].minValue == 0) revert InvalidReward();
            if (buckets_[i].maxValue == 0) revert InvalidReward();
            if (buckets_[i].minValue > buckets_[i].maxValue) revert InvalidReward();
            if (buckets_[i].minValue < minReward) revert InvalidReward();
            if (buckets_[i].maxValue > maxReward) revert InvalidReward();
        }

        // Validate bucket's are in ascending value range
        uint256 totalOdds = 0;
        for (uint256 i = 0; i < buckets_.length; i++) {
            if (i < buckets_.length - 1 && buckets_[i].maxValue >= buckets_[i + 1].minValue) revert InvalidBuckets();
            if (buckets_[i].oddsBps == 0) revert InvalidBuckets();
            if (buckets_[i].oddsBps > 10000) revert InvalidBuckets();

            // Sum individual probabilities
            totalOdds += buckets_[i].oddsBps;
        }

        // Final total odds check - must equal 10000 (100%)
        if (totalOdds != 10000) revert InvalidBuckets();

        // Hash pack for cosigner validation and event emission
        // Pack data gets re-checked in commitSignature on fulfill
        bytes32 packHash = hashPack(packPrice, buckets_);
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
            payoutBps: payoutBps,
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
    /// @param expectedRng_ Expected RNG value
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param commitSignature_ Signature used for commit data
    /// @param orderSignature_ Signature used for orderData (and to validate orderData)
    /// @param choice_ Choice made by the receiver (Payout = 0, NFT = 1)
    /// @param choiceSignature_ Signature used for receiver's choice (only required for NFT choice)
    /// @dev Emits a Fulfillment event on success
    function fulfill(
        uint256 commitId_,
        uint256 expectedRng_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata commitSignature_,
        bytes calldata orderSignature_,
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) public payable whenNotPaused {
        _fulfill(
            commitId_,
            expectedRng_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            commitSignature_,
            orderSignature_,
            choice_,
            choiceSignature_
        );
    }

    function _fulfill(
        uint256 commitId_,
        uint256 expectedRng_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata commitSignature_,
        bytes calldata orderSignature_,
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) internal nonReentrant {
        // Basic validation of tx
        if (msg.value > 0) _depositTreasury(msg.value);
        if (orderAmount_ > treasuryBalance) revert InsufficientBalance();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isCancelled[commitId_]) revert CommitIsCancelled();
        if (commitId_ >= packs.length) revert InvalidCommitId();

        CommitData memory commitData = packs[commitId_];

        // Check the cosigner signed the commit
        address commitCosigner = verifyCommit(commitData, commitSignature_);
        if (commitCosigner != commitData.cosigner) revert InvalidCosigner();
        if (!isCosigner[commitCosigner]) revert InvalidCosigner();

        // Validate the RNG
        uint256 rng = PRNG.rng(commitSignature_);
        if (rng != expectedRng_) revert InvalidRng();

        bytes32 digest = hashCommit(commitData);

        // Check the cosigner signed the order
        bytes32 orderHash = hashOrder(digest, marketplace_, orderAmount_, orderData_, token_, tokenId_);
        address orderCosigner = verifyHash(orderHash, orderSignature_);
        if (orderCosigner != commitData.cosigner) revert InvalidCosigner();
        if (!isCosigner[orderCosigner]) revert InvalidCosigner();

        // Determine bucket and validate orderAmount is within bucket range
        uint256 bucketIndex = _getBucketIndex(rng, commitData.buckets);
        BucketData memory bucket = commitData.buckets[bucketIndex];
        if (orderAmount_ < bucket.minValue) revert InvalidAmount();
        if (orderAmount_ > bucket.maxValue) revert InvalidAmount();

        // Check the fulfillment option
        bytes32 choiceHash = hashChoice(digest, choice_);
        address choiceSigner = verifyHash(choiceHash, choiceSignature_);
        if (choiceSigner != commitData.receiver && choiceSigner != commitData.cosigner) revert InvalidChoiceSigner();

        // If the user wants to fulfill via NFT but the option has expired, default to payout
        FulfillmentOption fulfillmentType = choice_;
        if (choice_ == FulfillmentOption.NFT && block.timestamp > nftFulfillmentExpiresAt[commitId_]) {
            fulfillmentType = FulfillmentOption.Payout;
        }

        // Mark the commit as fulfilled
        isFulfilled[commitId_] = true;

        // Collect the commit balance
        // Transfer the commit balance to the contract
        treasuryBalance += commitData.packPrice;
        commitBalance -= commitData.packPrice;

        // Handle user choice and fulfil order or payout
        if (fulfillmentType == FulfillmentOption.NFT) {
            // execute the market data to transfer the nft
            bool success = _fulfillOrder(marketplace_, orderData_, orderAmount_);
            if (success) {
                // subtract the order amount from the contract balance
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
        } else if (fulfillmentType == FulfillmentOption.Payout) {
            // Payout fulfillment route
            // Calculate payout amount based on NFT value and payoutBps
            uint256 payoutAmount = (orderAmount_ * payoutBps) / 10000;

            (bool success,) = commitData.receiver.call{value: payoutAmount}("");
            if (success) {
                treasuryBalance -= payoutAmount;
            } else {
                emit TransferFailure(commitData.id, commitData.receiver, payoutAmount, digest);
            }
            // emit the payout
            emit Fulfillment(
                msg.sender,
                commitId_,
                rng,
                bucket.oddsBps,
                bucketIndex,
                payoutAmount,
                address(0), // no NFT token address for payout
                0, // no NFT token ID for payout
                0, // no NFT amount for payout
                commitData.receiver,
                choiceSigner,
                choice_,
                fulfillmentType,
                digest
            );
        } else {
            revert InvalidFulfillmentOption();
        }
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitDigest_ Digest of the commit to fulfill
    /// @param expectedRng_ Expected RNG value
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param commitSignature_ Signature used for commit data
    /// @param orderSignature_ Signature used for commit data
    /// @param choice_ Choice made by the receiver
    /// @param choiceSignature_ Signature used for receiver's choice
    /// @dev Emits a Fulfillment event on success
    function fulfillByDigest(
        bytes32 commitDigest_,
        uint256 expectedRng_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata commitSignature_,
        bytes calldata orderSignature_,
        FulfillmentOption choice_,
        bytes calldata choiceSignature_
    ) public payable whenNotPaused {
        return fulfill(
            commitIdByDigest[commitDigest_],
            expectedRng_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            commitSignature_,
            orderSignature_,
            choice_,
            choiceSignature_
        );
    }

    /// @notice Allows the admin to withdraw ETH from the contract balance
    /// @param amount The amount of ETH to withdraw
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function withdraw(uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > treasuryBalance) revert InsufficientBalance();
        treasuryBalance -= amount;

        (bool success,) = payable(feeReceiver).call{value: amount}("");
        if (!success) revert WithdrawalFailed();

        emit Withdrawal(msg.sender, amount, feeReceiver);
    }

    /// @notice Allows the admin to withdraw all ETH from the contract
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function emergencyWithdraw() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryBalance = 0;
        commitBalance = 0;

        uint256 currentBalance = address(this).balance;

        _rescueETH(feeReceiver, currentBalance);

        _pause();
        emit Withdrawal(msg.sender, currentBalance, feeReceiver);
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
    function setMaxReward(uint256 maxReward_) external onlyRole(OPS_ROLE) {
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
        if (minReward_ < minReward) revert InvalidReward();

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

    /// @notice Sets the payout basis points
    /// @param payoutBps_ New payout basis points
    /// @dev Only callable by admin role
    /// @dev Emits a PayoutBpsUpdated event
    function setPayoutBps(uint256 payoutBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (payoutBps_ > 10000) revert InvalidPayoutBps();
        uint256 oldPayoutBps = payoutBps;
        payoutBps = payoutBps_;
        emit PayoutBpsUpdated(oldPayoutBps, payoutBps_);
    }

    /// @notice Deposits ETH into the treasury
    /// @dev Called internally when receiving ETH
    /// @param amount Amount of ETH to deposit
    function _depositTreasury(uint256 amount) internal {
        treasuryBalance += amount;
        emit Deposit(msg.sender, amount);
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

    /// @notice Transfers the fee receiver manager role
    /// @param newFeeReceiverManager_ New fee receiver manager
    /// @dev Only callable by fee receiver manager role
    function transferFeeReceiverManager(address newFeeReceiverManager_) external onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        if (newFeeReceiverManager_ == address(0)) {
            revert InvalidFeeReceiverManager();
        }
        _transferFeeReceiverManager(newFeeReceiverManager_);
    }

    /// @notice Transfers the fee receiver manager role
    /// @param newFeeReceiverManager_ New fee receiver manager
    function _transferFeeReceiverManager(address newFeeReceiverManager_) internal {
        _revokeRole(FEE_RECEIVER_MANAGER_ROLE, msg.sender);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, newFeeReceiverManager_);
        emit FeeReceiverManagerTransferred(msg.sender, newFeeReceiverManager_);
    }

    /// @notice Sets the fee receiver
    /// @param feeReceiver_ Address to set as fee receiver
    /// @dev Only callable by fee receiver manager role
    function setFeeReceiver(address feeReceiver_) external onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        _setFeeReceiver(feeReceiver_);
    }

    /// @notice Sets the fee receiver
    /// @param feeReceiver_ Address to set as fee receiver
    function _setFeeReceiver(address feeReceiver_) internal {
        if (feeReceiver_ == address(0)) revert InvalidFeeReceiver();
        if (hasRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiver_)) {
            revert InvalidFeeReceiverManager();
        }
        address oldFeeReceiver = feeReceiver;
        feeReceiver = payable(feeReceiver_);
        emit FeeReceiverUpdated(oldFeeReceiver, feeReceiver_);
    }
}
