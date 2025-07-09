// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./common/SignatureVerifier.sol";

import {IERC1155MInitializableV1_0_2} from "./common/interfaces/IERC1155MInitializableV1_0_2.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./common/MEAccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";
import {TokenRescuer} from "./common/TokenRescuer.sol";

contract LuckyBuy is
    MEAccessControl,
    Pausable,
    SignatureVerifier,
    ReentrancyGuard,
    TokenRescuer
{
    IPRNG public PRNG;
    address payable public feeReceiver;
    // We will not track our supply on this contract. We will mint a yuge amount and never run out on the oe.
    address public openEditionToken;
    uint256 public openEditionTokenId;
    // The OE interface forces us to use uint32
    uint32 public openEditionTokenAmount;

    CommitData[] public luckyBuys;
    mapping(bytes32 commitDigest => uint256 commitId) public commitIdByDigest;

    uint256 public treasuryBalance; // The contract balance
    uint256 public commitBalance; // The open commit balances
    uint256 public protocolBalance; // The protocol fees for the open commits

    uint256 public maxReward = 50 ether;
    uint256 public protocolFee = 0;
    uint256 public minReward = BASE_POINTS;
    uint256 public flatFee = 0;
    uint256 public bulkCommitFee = 0;

    uint256 public maxBulkSize = 20;

    uint256 public bulkSessionCounter;

    uint256 public commitExpireTime = 1 days;
    mapping(uint256 commitId => uint256 expiresAt) public commitExpiresAt;

    uint256 public constant MIN_COMMIT_EXPIRE_TIME = 1 minutes;
    uint256 public constant ONE_PERCENT = 100;
    uint256 public constant BASE_POINTS = 10000;

    bytes32 public constant FEE_RECEIVER_MANAGER_ROLE =
        keccak256("FEE_RECEIVER_MANAGER_ROLE");

    mapping(address cosigner => bool active) public isCosigner;
    mapping(address receiver => uint256 counter) public luckyBuyCount;
    mapping(uint256 commitId => bool fulfilled) public isFulfilled;
    mapping(uint256 commitId => bool expired) public isExpired;
    // We track this because we can change the fees at any time. This allows open commits to be fulfilled/returned with the fees at the time of commit
    mapping(uint256 commitId => uint256 fee) public feesPaid;

    event Commit(
        address indexed sender,
        uint256 indexed commitId,
        address indexed receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        bytes32 orderHash,
        uint256 amount,
        uint256 reward,
        uint256 protocolFee,
        uint256 flatFee,
        bytes32 digest,
        uint256 bulkSessionId
    );
    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);
    event Fulfillment(
        bytes32 indexed digest,
        address indexed receiver,
        uint256 commitId,
        address cosigner,
        uint256 commitAmount,
        uint256 orderAmount,
        address token,
        uint256 tokenId,
        uint256 rng,
        uint256 odds,
        bool win,
        bool orderSuccess,
        uint256 protocolFee,
        uint256 flatFee
    );
    event MaxRewardUpdated(uint256 oldMaxReward, uint256 newMaxReward);
    event ProtocolFeeUpdated(uint256 oldProtocolFee, uint256 newProtocolFee);
    event Withdrawal(
        address indexed sender,
        uint256 amount,
        address feeReceiver
    );
    event Deposit(address indexed sender, uint256 amount);
    event MinRewardUpdated(uint256 oldMinReward, uint256 newMinReward);
    event CommitExpireTimeUpdated(
        uint256 oldCommitExpireTime,
        uint256 newCommitExpireTime
    );
    event CommitExpired(uint256 indexed commitId, bytes32 digest);
    event OpenEditionTokenSet(
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount
    );
    event FlatFeeUpdated(uint256 oldFlatFee, uint256 newFlatFee);
    event BulkCommitFeeUpdated(uint256 oldBulkCommitFee, uint256 newBulkCommitFee);
    event BulkCommit(
        address indexed sender,
        uint256 indexed bulkSessionId,
        uint256 numberOfCommits
    );
    event BulkExpire(
        address indexed sender,
        uint256 numberOfCommits
    );
    event FeeReceiverUpdated(
        address indexed oldFeeReceiver,
        address indexed newFeeReceiver
    );
    event OpenEditionContractTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );
    event FeeSplit(
        uint256 indexed commitId,
        address indexed feeSplitReceiver,
        uint256 feeSplitPercentage,
        uint256 totalProtocolFee,
        uint256 splitAmount
    );
    event FeeTransferFailure(
        uint256 indexed commitId,
        address indexed feeSplitReceiver,
        uint256 amount,
        bytes32 digest
    );
    event FeeReceiverManagerTransferred(
        address indexed oldFeeReceiverManager,
        address indexed newFeeReceiverManager
    );
    event TransferFailure(
        uint256 indexed commitId,
        address indexed receiver,
        uint256 amount,
        bytes32 digest
    );

    error AlreadyCosigner();
    error AlreadyFulfilled();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidCommitOwner();
    error InvalidCosigner();
    error InvalidOrderHash();
    error InvalidProtocolFee();
    error InvalidBulkCommitFee();
    error InvalidReceiver();
    error InvalidReward();
    error FulfillmentFailed();
    error InvalidCommitId();
    error WithdrawalFailed();
    error InvalidCommitExpireTime();
    error CommitIsExpired();
    error CommitNotExpired();
    error TransferFailed();
    error InvalidFeeReceiver();
    error InvalidFeeSplitReceiver();
    error InvalidFeeSplitPercentage();
    error InvalidFeeReceiverManager();
    error InvalidBulkSize();

    // Bulk operation structs
    struct CommitRequest {
        address receiver;
        address cosigner;
        uint256 seed;
        bytes32 orderHash;
        uint256 reward;
        uint256 amount; // Amount of ETH to commit for this specific request
    }

    struct FulfillRequest {
        bytes32 commitDigest;
        address marketplace;
        bytes orderData;
        uint256 orderAmount;
        address token;
        uint256 tokenId;
        bytes signature;
        address feeSplitReceiver;
        uint256 feeSplitPercentage;
    }

    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (
            luckyBuys[commitId_].receiver != msg.sender &&
            luckyBuys[commitId_].cosigner != msg.sender
        ) revert InvalidCommitOwner();
        _;
    }

    /// @notice Constructor initializes the contract and handles any pre-existing balance
    /// @dev Sets up EIP712 domain separator and deposits any ETH sent during deployment
    constructor(
        uint256 protocolFee_,
        uint256 flatFee_,
        uint256 bulkCommitFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    ) MEAccessControl() SignatureVerifier("LuckyBuy", "1") {
        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setBulkCommitFee(bulkCommitFee_);
        _setFeeReceiver(feeReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);
    }

    /// @notice Allows a user to commit funds for a chance to win
    /// @param receiver_ Address that will receive the NFT/ETH if won
    /// @param cosigner_ Address of the authorized cosigner
    /// @param seed_ Random seed for the commit
    /// @param orderHash_ Hash of the order details
    /// @param reward_ Amount of reward if won
    /// @dev Emits a Commit event on success
    /// @return commitId The ID of the created commit
    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        bytes32 orderHash_,
        uint256 reward_
    ) public payable whenNotPaused returns (uint256) {
        if (msg.value == 0) revert InvalidAmount();
        
        CommitRequest memory request = CommitRequest({
            receiver: receiver_,
            cosigner: cosigner_,
            seed: seed_,
            orderHash: orderHash_,
            reward: reward_,
            amount: msg.value
        });
        
        return _processCommit(request, protocolFee, 0); // 0 = individual commit
    }

    /// @notice Allows a user to commit funds for multiple chances to win in a single transaction
    /// @param requests_ Array of commit requests
    /// @dev User must send exact total amount needed for all commits including fees
    /// @dev Applies a bulk commit premium fee (on top of protocol fee) to each individual commit
    /// @dev Emits a Commit event for each successful commit with the same bulkSessionId for tracking
    /// @return commitIds Array of created commit IDs
    function bulkCommit(
        CommitRequest[] calldata requests_
    ) public payable whenNotPaused returns (uint256[] memory commitIds) {
        if (requests_.length == 0) revert InvalidAmount();
        if (requests_.length > maxBulkSize) revert InvalidBulkSize();
        
        commitIds = new uint256[](requests_.length);
        uint256 totalUsed = 0;
        
                // Generate unique bulk session ID for this transaction
        uint256 currentBulkSessionId = ++bulkSessionCounter;
        
        // Calculate total fee rate for bulk commits (protocol fee + bulk premium)
        uint256 totalFeeRate = protocolFee + bulkCommitFee;

        // Process each commit and validate amounts as we go
        for (uint256 i = 0; i < requests_.length; i++) {
            CommitRequest calldata request = requests_[i];

            // Basic amount validation
            if (request.amount == 0) revert InvalidAmount();
            totalUsed += request.amount;

            // Early check if we're exceeding msg.value
            if (totalUsed > msg.value) revert InvalidAmount();

            commitIds[i] = _processCommit(request, totalFeeRate, currentBulkSessionId);
        }

        // Final validation that exact amount was sent
        if (totalUsed != msg.value) revert InvalidAmount();

        // Emit event after successful completion
        emit BulkCommit(msg.sender, currentBulkSessionId, requests_.length);

        return commitIds;
    }
    
    /// @notice Internal function to process a single commit
    /// @param request_ The commit request to process
    /// @param feeRate_ The fee rate to apply (in basis points)
    /// @param bulkSessionId_ The bulk session ID (0 for individual commits, >0 for bulk commits)
    /// @return commitId The ID of the created commit
    function _processCommit(
        CommitRequest memory request_,
        uint256 feeRate_,
        uint256 bulkSessionId_
    ) internal returns (uint256 commitId) {
        uint256 amountWithoutFlatFee = request_.amount - flatFee;
        uint256 commitAmount = calculateContributionWithoutFee(amountWithoutFlatFee, feeRate_);
        
        // All validations handled by _validateCommit
        _validateCommit(request_.receiver, request_.cosigner, request_.reward, commitAmount);
        
        // Handle flat fee payment
        _handleFlatFeePayment();
        
        // Calculate protocol fee using the provided fee rate
        uint256 protocolFeeAmount = amountWithoutFlatFee - commitAmount;
        
        // Create commit
        commitId = luckyBuys.length;
        uint256 userCounter = luckyBuyCount[request_.receiver]++;
        
        // Update balances
        feesPaid[commitId] = protocolFeeAmount;
        protocolBalance += protocolFeeAmount;
        commitBalance += commitAmount;
        
        // Store commit data
        CommitData memory commitData = CommitData({
            id: commitId,
            receiver: request_.receiver,
            cosigner: request_.cosigner,
            seed: request_.seed,
            counter: userCounter,
            orderHash: request_.orderHash,
            amount: commitAmount,
            reward: request_.reward
        });
        
        luckyBuys.push(commitData);
        commitExpiresAt[commitId] = block.timestamp + commitExpireTime;
        
        bytes32 digest = hash(commitData);
        commitIdByDigest[digest] = commitId;
        
        emit Commit(
            msg.sender,
            commitId,
            request_.receiver,
            request_.cosigner,
            request_.seed,
            userCounter,
            request_.orderHash,
            commitAmount,
            request_.reward,
            protocolFeeAmount,
            flatFee,
            digest,
            bulkSessionId_
        );
    }
    
    /// @notice Internal function to handle flat fee payment
    function _handleFlatFeePayment() internal {
        if (flatFee > 0 && feeReceiver != address(0)) {
            (bool success, ) = feeReceiver.call{value: flatFee}("");
            if (!success) revert TransferFailed();
        } else {
            treasuryBalance += flatFee;
        }
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitId_ ID of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param signature_ Signature used for random number generation
    /// @param feeSplitReceiver_ Address of the fee split receiver (address(0) for no split)
    /// @param feeSplitPercentage_ Percentage of the fee to split (0 for no split)
    /// @dev Emits a Fulfillment event on success
    /// @dev Emits a FeeSplit event if fee splitting is enabled
    function fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_,
        address feeSplitReceiver_,
        uint256 feeSplitPercentage_
    ) public payable whenNotPaused {
        // Validate fee split parameters if provided
        if (feeSplitReceiver_ != address(0) || feeSplitPercentage_ > 0) {
            if (feeSplitReceiver_ == address(0)) revert InvalidFeeSplitReceiver();
            if (feeSplitReceiver_ == address(this)) revert InvalidFeeSplitReceiver();
            if (feeSplitPercentage_ > BASE_POINTS) revert InvalidFeeSplitPercentage();
        }

        uint256 protocolFeesPaid = feesPaid[commitId_];
        
        _fulfill(
            commitId_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            signature_
        );

        // Handle fee splitting if enabled
        if (feeSplitReceiver_ != address(0) && feeSplitPercentage_ > 0) {
            uint256 splitAmount = (protocolFeesPaid * feeSplitPercentage_) / BASE_POINTS;
            
            (bool success, ) = payable(feeSplitReceiver_).call{value: splitAmount}("");
            if (!success) {
                emit FeeTransferFailure(
                    commitId_,
                    feeSplitReceiver_,
                    splitAmount,
                    hash(luckyBuys[commitId_])
                );
            } else {
                treasuryBalance -= splitAmount;
            }
            
            uint256 remainingProtocolFees = protocolFeesPaid - splitAmount;
            _sendProtocolFees(commitId_, remainingProtocolFees);
            
            emit FeeSplit(
                commitId_,
                feeSplitReceiver_,
                feeSplitPercentage_,
                protocolFeesPaid,
                splitAmount
            );
        } else {
            // No fee split, send all protocol fees normally
            _sendProtocolFees(commitId_, protocolFeesPaid);
        }
    }





    function _fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) internal nonReentrant {
        if (msg.value > 0) _depositTreasury(msg.value);

        (CommitData memory commitData, bytes32 digest) = _validateFulfillment(
            commitId_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            signature_
        );

        // mark the commit as fulfilled
        isFulfilled[commitId_] = true;

        // Collect the commit balance and protocol fees
        // transfer the commit balance to the contract
        treasuryBalance += commitData.amount;
        commitBalance -= commitData.amount;

        // transfer the protocol fees to the contract
        uint256 protocolFeesPaid = feesPaid[commitData.id];

        treasuryBalance += protocolFeesPaid;
        protocolBalance -= protocolFeesPaid;

        // Check if we have enough balance after collecting all funds
        if (orderAmount_ > treasuryBalance) revert InsufficientBalance();

        // calculate the odds in base points
        uint256 odds = _calculateOdds(commitData.amount, commitData.reward);
        uint256 rng = PRNG.rng(signature_);
        bool win = rng < odds;

        if (win) {
            _handleWin(
                commitData,
                marketplace_,
                orderData_,
                orderAmount_,
                rng,
                odds,
                win,
                token_,
                tokenId_,
                protocolFeesPaid,
                digest,
                signature_
            );
        } else {
            if (openEditionToken != address(0)) {
                IERC1155MInitializableV1_0_2(openEditionToken).ownerMint(
                    commitData.receiver,
                    openEditionTokenId,
                    openEditionTokenAmount
                );
            }
            // emit the failure
            emit Fulfillment(
                digest,
                commitData.receiver,
                commitData.id,
                commitData.cosigner,
                commitData.amount,
                commitData.reward,
                token_,
                tokenId_,
                rng,
                odds,
                win,
                false,
                protocolFeesPaid,
                flatFee
            );
        }
    }





    /// @notice Fulfills a commit by digest with the result of the random number generation
    /// @param commitDigest_ Digest of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param signature_ Signature used for random number generation
    /// @param feeSplitReceiver_ Address of the fee split receiver (address(0) for no split)
    /// @param feeSplitPercentage_ Percentage of the fee to split (0 for no split)
    /// @dev Emits a Fulfillment event on success
    /// @dev Emits a FeeSplit event if fee splitting is enabled
    function fulfillByDigest(
        bytes32 commitDigest_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_,
        address feeSplitReceiver_,
        uint256 feeSplitPercentage_
    ) public payable whenNotPaused {
        return
            fulfill(
                commitIdByDigest[commitDigest_],
                marketplace_,
                orderData_,
                orderAmount_,
                token_,
                tokenId_,
                signature_,
                feeSplitReceiver_,
                feeSplitPercentage_
            );
    }



    /// @notice Fulfills multiple commits in a single transaction
    /// @param requests_ Array of fulfill requests (each with its own commit digest and fee split configuration)
    /// @dev Anyone can call this function as long as they have valid cosigner signatures
    /// @dev Emits a Fulfillment event for each successful fulfill
    /// @dev Emits a FeeSplit event for each fulfill if fee splitting is enabled
    function bulkFulfill(
        FulfillRequest[] calldata requests_
    ) public payable whenNotPaused {
        if (requests_.length == 0) revert InvalidAmount();
        
        if (msg.value > 0) _depositTreasury(msg.value);
        
        for (uint256 i = 0; i < requests_.length; i++) {
            FulfillRequest calldata request = requests_[i];
            uint256 commitId = commitIdByDigest[request.commitDigest];
            
            // Validate fee split parameters for this specific request
            if (request.feeSplitReceiver != address(0) || request.feeSplitPercentage > 0) {
                if (request.feeSplitReceiver == address(0)) revert InvalidFeeSplitReceiver();
                if (request.feeSplitReceiver == address(this)) revert InvalidFeeSplitReceiver();
                if (request.feeSplitPercentage > BASE_POINTS) revert InvalidFeeSplitPercentage();
            }
            
            uint256 protocolFeesPaid = feesPaid[commitId];
            
            _fulfill(
                commitId,
                request.marketplace,
                request.orderData,
                request.orderAmount,
                request.token,
                request.tokenId,
                request.signature
            );
            
            // Handle fee splitting if enabled for this request
            if (request.feeSplitReceiver != address(0) && request.feeSplitPercentage > 0) {
                uint256 splitAmount = (protocolFeesPaid * request.feeSplitPercentage) / BASE_POINTS;
                
                (bool success, ) = payable(request.feeSplitReceiver).call{value: splitAmount}("");
                if (!success) {
                    emit FeeTransferFailure(
                        commitId,
                        request.feeSplitReceiver,
                        splitAmount,
                        hash(luckyBuys[commitId])
                    );
                } else {
                    treasuryBalance -= splitAmount;
                }
                
                uint256 remainingProtocolFees = protocolFeesPaid - splitAmount;
                _sendProtocolFees(commitId, remainingProtocolFees);
                
                emit FeeSplit(
                    commitId,
                    request.feeSplitReceiver,
                    request.feeSplitPercentage,
                    protocolFeesPaid,
                    splitAmount
                );
            } else {
                // No fee split, send all protocol fees normally
                _sendProtocolFees(commitId, protocolFeesPaid);
            }
        }
    }



    function _handleWin(
        CommitData memory commitData,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        uint256 rng_,
        uint256 odds_,
        bool win_,
        address token_,
        uint256 tokenId_,
        uint256 protocolFeesPaid,
        bytes32 digest,
        bytes calldata signature_
    ) internal {
        // execute the market data to transfer the nft
        bool success = _fulfillOrder(marketplace_, orderData_, orderAmount_);
        if (success) {
            // subtract the order amount from the contract balance
            treasuryBalance -= orderAmount_;
            // emit a success transfer for the nft
            emit Fulfillment(
                digest,
                commitData.receiver,
                commitData.id,
                commitData.cosigner,
                commitData.amount,
                orderAmount_,
                token_,
                tokenId_,
                rng_,
                odds_,
                win_,
                success,
                protocolFeesPaid,
                flatFee
            );
        } else {
            // The order failed to fulfill, it could be bought already or invalid, make the best effort to send the user the value of the order they won.
            (bool success, ) = commitData.receiver.call{value: orderAmount_}("");
            if (success) {
                treasuryBalance -= orderAmount_;
            } else {
                emit TransferFailure(commitData.id, commitData.receiver, orderAmount_, digest);
            }

            emit Fulfillment(
                digest,
                commitData.receiver,
                commitData.id,
                commitData.cosigner,
                commitData.amount,
                orderAmount_,
                token_,
                tokenId_,
                rng_,
                odds_,
                win_,
                false,
                protocolFeesPaid,
                flatFee
            );
        }
    }

    /// @notice Allows the admin to withdraw ETH from the contract balance
    /// @param amount The amount of ETH to withdraw
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function withdraw(
        uint256 amount
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > treasuryBalance) revert InsufficientBalance();
        treasuryBalance -= amount;

        (bool success, ) = payable(feeReceiver).call{value: amount}("");
        if (!success) revert WithdrawalFailed();

        emit Withdrawal(msg.sender, amount, feeReceiver);
    }

    /// @notice Allows the admin to withdraw all ETH from the contract
    /// @dev Only callable by admin role
    /// @dev Emits a Withdrawal event
    function emergencyWithdraw()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        treasuryBalance = 0;
        commitBalance = 0;
        protocolBalance = 0;

        uint256 currentBalance = address(this).balance;

        _rescueETH(feeReceiver, currentBalance);

        _pause();
        emit Withdrawal(msg.sender, currentBalance, feeReceiver);
    }

    /// @notice Allows the commit owner to expire a commit in the event that the commit is not or cannot be fulfilled
    /// @param commitId_ ID of the commit to expire
    /// @dev Only callable by the commit owner
    /// @dev Emits a CommitExpired event
    function expire(
        uint256 commitId_
    ) external onlyCommitOwnerOrCosigner(commitId_) nonReentrant {
        _expire(commitId_);
    }

    /// @notice Allows bulk expiration of multiple commits in a single transaction
    /// @param commitIds_ Array of commit IDs to expire
    /// @dev Only callable by the commit owner or cosigner for each commit
    /// @dev Emits a CommitExpired event for each successful expiration
    /// @dev Emits a BulkExpire event after successful completion
    function bulkExpire(
        uint256[] calldata commitIds_
    ) external nonReentrant {
        if (commitIds_.length == 0) revert InvalidAmount();
        if (commitIds_.length > maxBulkSize) revert InvalidBulkSize();

        // Process each expiration
        for (uint256 i = 0; i < commitIds_.length; i++) {
            uint256 commitId = commitIds_[i];

            // Validate ownership for each commit
            if (
                luckyBuys[commitId].receiver != msg.sender &&
                luckyBuys[commitId].cosigner != msg.sender
            ) revert InvalidCommitOwner();

            _expire(commitId);
        }

        // Emit event after successful completion
        emit BulkExpire(msg.sender, commitIds_.length);
    }

    /// @notice Internal function to expire a commit
    /// @param commitId_ ID of the commit to expire
    /// @dev Validates expiration conditions and processes the expiration
    /// @dev Emits a CommitExpired event
    function _expire(uint256 commitId_) internal {
        if (commitId_ >= luckyBuys.length) revert InvalidCommitId();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isExpired[commitId_]) revert CommitIsExpired();
        if (block.timestamp < commitExpiresAt[commitId_])
            revert CommitNotExpired();

        isExpired[commitId_] = true;

        CommitData memory commitData = luckyBuys[commitId_];

        uint256 commitAmount = commitData.amount;
        commitBalance -= commitAmount;

        uint256 protocolFeesPaid = feesPaid[commitId_];
        protocolBalance -= protocolFeesPaid;

        uint256 transferAmount = commitAmount + protocolFeesPaid;

        (bool success, ) = payable(commitData.receiver).call{
            value: transferAmount
        }("");
        if (!success) {
            treasuryBalance += transferAmount;
            emit TransferFailure(
                commitId_,
                commitData.receiver,
                transferAmount,
                hash(commitData)
            );
        }

        emit CommitExpired(commitId_, hash(commitData));
    }

    /// @notice Calculate contribution amount with custom fee rate
    /// @param amount The original amount including fee
    /// @param feeRate The fee rate to apply (in basis points)
    /// @return The contribution amount without the fee
    /// @dev Uses formula: contribution = (amount * FEE_DENOMINATOR) / (FEE_DENOMINATOR + feePercent)
    /// @dev This ensures fee isn't charged on the fee portion itself
    function calculateContributionWithoutFee(
        uint256 amount,
        uint256 feeRate
    ) public view returns (uint256) {
        return (amount * BASE_POINTS) / (BASE_POINTS + feeRate);
    }

    // Internal validation helpers have been moved to the dedicated
    // INTERNAL FUNCTIONS section further below.

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // ############################################################
    // ############ MANAGEMENT ############
    // ############################################################

    function transferOpenEditionContractOwnership(
        address newOwner
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldOwner = IERC1155MInitializableV1_0_2(openEditionToken)
            .owner();
        IERC1155MInitializableV1_0_2(openEditionToken).transferOwnership(
            newOwner
        );

        _setOpenEditionToken(
            openEditionToken,
            openEditionTokenId,
            openEditionTokenAmount
        );

        emit OpenEditionContractTransferred(oldOwner, newOwner);
    }

    // ############################################################
    // ############ RESCUE FUNCTIONS ############
    // ############################################################

    function rescueERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(RESCUE_ROLE) {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        amounts[0] = amount;

        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721(
        address token,
        address to,
        uint256 tokenId
    ) external onlyRole(RESCUE_ROLE) {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;

        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155(
        address token,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external onlyRole(RESCUE_ROLE) {
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

    function rescueERC20Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata amounts
    ) external onlyRole(RESCUE_ROLE) {
        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds
    ) external onlyRole(RESCUE_ROLE) {
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

    /// @notice Sets the open edition token. We allow address(0) here.
    /// @param token_ Address of the open edition token
    /// @param tokenId_ ID of the open edition token
    /// @param amount_ Amount of the open edition token. The OE interface forces us to use uint32
    /// @dev Only callable by ops role
    function setOpenEditionToken(
        address token_,
        uint256 tokenId_,
        uint32 amount_
    ) external onlyRole(OPS_ROLE) {
        _setOpenEditionToken(token_, tokenId_, amount_);
    }

    function _setOpenEditionToken(
        address token_,
        uint256 tokenId_,
        uint32 amount_
    ) internal {
        if (address(token_) == address(0)) {
            openEditionToken = address(0);
            openEditionTokenId = 0;
            openEditionTokenAmount = 0;
        } else {
            if (amount_ == 0) revert InvalidAmount();

            openEditionToken = token_;
            openEditionTokenId = tokenId_;
            openEditionTokenAmount = amount_;
        }
        emit OpenEditionTokenSet(
            openEditionToken,
            openEditionTokenId,
            openEditionTokenAmount
        );
    }

    /// @notice Adds a new authorized cosigner
    /// @param cosigner_ Address to add as cosigner
    /// @dev Only callable by admin role
    /// @dev Emits a CoSignerAdded event
    function addCosigner(
        address cosigner_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (cosigner_ == address(0)) revert InvalidCosigner();
        if (isCosigner[cosigner_]) revert AlreadyCosigner();
        isCosigner[cosigner_] = true;
        emit CosignerAdded(cosigner_);
    }

    /// @notice Removes an authorized cosigner
    /// @param cosigner_ Address to remove as cosigner
    /// @dev Only callable by admin role
    /// @dev Emits a CoSignerRemoved event
    function removeCosigner(
        address cosigner_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isCosigner[cosigner_]) revert InvalidCosigner();
        isCosigner[cosigner_] = false;
        emit CosignerRemoved(cosigner_);
    }

    /// @notice Sets the commit expire time.
    /// @param commitExpireTime_ New commit expire time
    /// @dev Only callable by admin role
    /// @dev Emits a CommitExpireTimeUpdated event
    function setCommitExpireTime(
        uint256 commitExpireTime_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (commitExpireTime_ < MIN_COMMIT_EXPIRE_TIME)
            revert InvalidCommitExpireTime();
        uint256 oldCommitExpireTime = commitExpireTime;
        commitExpireTime = commitExpireTime_;
        emit CommitExpireTimeUpdated(oldCommitExpireTime, commitExpireTime_);
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
    function setMinReward(
        uint256 minReward_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (minReward_ > maxReward) revert InvalidReward();
        if (minReward_ < BASE_POINTS) revert InvalidReward();

        uint256 oldMinReward = minReward;
        minReward = minReward_;

        emit MinRewardUpdated(oldMinReward, minReward_);
    }

    /// @notice Sets the bulk commit fee. Is a percentage fee applied to bulk commits
    /// @param bulkCommitFee_ New bulk commit fee in basis points
    /// @dev Only callable by ops role
    /// @dev Emits a BulkCommitFeeUpdated event
    function setBulkCommitFee(uint256 bulkCommitFee_) external onlyRole(OPS_ROLE) {
        _setBulkCommitFee(bulkCommitFee_);
    }

    function _setBulkCommitFee(uint256 bulkCommitFee_) internal {
        if (bulkCommitFee_ > BASE_POINTS) revert InvalidBulkCommitFee();
        uint256 oldBulkCommitFee = bulkCommitFee;
        bulkCommitFee = bulkCommitFee_;
        emit BulkCommitFeeUpdated(oldBulkCommitFee, bulkCommitFee_);
    }

    /// @notice Sets the maximum bulk size for commit operations.
    /// @param maxBulkSize_ New maximum bulk size.
    /// @dev Only callable by admin role.
    /// @dev Emits a MaxBulkSizeUpdated event.
    function setMaxBulkSize(uint256 maxBulkSize_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxBulkSize_ < 1) revert InvalidBulkSize(); // Minimum size is 1
        maxBulkSize = maxBulkSize_;
    }

    /// @notice Gets the current maximum bulk size.
    /// @return The current maximum bulk size.
    function getMaxBulkSize() external view returns (uint256) {
        return maxBulkSize;
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

    // ############################################################
    // ############ INTERNAL FUNCTIONS ############
    // ############################################################

    function _validateCommit(
        address receiver_,
        address cosigner_,
        uint256 reward_,
        uint256 commitAmount
    ) internal view {
        if (cosigner_ == address(0) || !isCosigner[cosigner_]) {
            revert InvalidCosigner();
        }
        if (receiver_ == address(0)) {
            revert InvalidReceiver();
        }
        if (reward_ == 0 || reward_ > maxReward || reward_ < minReward) {
            revert InvalidReward();
        }
        if (
            commitAmount < (reward_ / ONE_PERCENT) || commitAmount > reward_
        ) {
            revert InvalidAmount();
        }
    }

    function _validateFulfillment(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) internal view returns (CommitData memory, bytes32) {
        if (commitId_ >= luckyBuys.length) revert InvalidCommitId();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isExpired[commitId_]) revert CommitIsExpired();

        CommitData memory commitData = luckyBuys[commitId_];

        if (
            commitData.orderHash !=
            hashOrder(marketplace_, orderAmount_, orderData_, token_, tokenId_)
        ) revert InvalidOrderHash();

        if (orderAmount_ != commitData.reward) revert InvalidAmount();

        bytes32 digest = hash(commitData);
        address cosigner = _verifyDigest(digest, signature_);
        if (cosigner != commitData.cosigner || !isCosigner[cosigner]) {
            revert InvalidCosigner();
        }

        return (commitData, digest);
    }

    /// @notice Calculates the odds of winning based on amount and reward
    /// @dev Internal function used in fulfill()
    /// @param amount Amount committed
    /// @param reward Potential reward
    /// @return odds The calculated odds as a percentage (0-100)
    function _calculateOdds(
        uint256 amount,
        uint256 reward
    ) internal pure returns (uint256) {
        return (amount * BASE_POINTS) / reward;
    }

    /// @notice Fulfills an order with the specified parameters
    /// @dev Internal function called by fulfill()
    /// @param to Address to send the transaction to
    /// @param data Calldata for the transaction
    /// @param amount Amount of ETH to send
    /// @return success Whether the transaction was successful
    function _fulfillOrder(
        address to,
        bytes calldata data,
        uint256 amount
    ) internal returns (bool success) {
        (success, ) = to.call{value: amount}(data);
    }

    function setProtocolFee(uint256 protocolFee_) external onlyRole(OPS_ROLE) {
        _setProtocolFee(protocolFee_);
    }

    function _setProtocolFee(uint256 protocolFee_) internal {
        if (protocolFee_ > BASE_POINTS) revert InvalidProtocolFee();
        uint256 oldProtocolFee = protocolFee;
        protocolFee = protocolFee_;
        emit ProtocolFeeUpdated(oldProtocolFee, protocolFee_);
    }

    /// @notice Sets the flat fee. Is a static amount that comes off the top of the commit amount.
    /// @param flatFee_ New flat fee
    /// @dev Only callable by ops role
    /// @dev Emits a FlatFeeUpdated event
    function setFlatFee(uint256 flatFee_) external onlyRole(OPS_ROLE) {
        _setFlatFee(flatFee_);
    }

    function _setFlatFee(uint256 flatFee_) internal {
        uint256 oldFlatFee = flatFee;
        flatFee = flatFee_;
        emit FlatFeeUpdated(oldFlatFee, flatFee_);
    }

    function transferFeeReceiverManager(
        address newFeeReceiverManager_
    ) external onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        if (newFeeReceiverManager_ == address(0))
            revert InvalidFeeReceiverManager();
        _transferFeeReceiverManager(newFeeReceiverManager_);
    }

    function _transferFeeReceiverManager(
        address newFeeReceiverManager_
    ) internal {
        _revokeRole(FEE_RECEIVER_MANAGER_ROLE, msg.sender);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, newFeeReceiverManager_);
        emit FeeReceiverManagerTransferred(msg.sender, newFeeReceiverManager_);
    }

    /// @notice Sets the fee receiver
    /// @param feeReceiver_ Address to set as fee receiver
    /// @dev Only callable by admin role
    /// @dev Emits a FeeReceiverUpdated event
    function setFeeReceiver(
        address feeReceiver_
    ) external onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        _setFeeReceiver(feeReceiver_);
    }

    function _setFeeReceiver(address feeReceiver_) internal {
        if (feeReceiver_ == address(0)) revert InvalidFeeReceiver();
        if (hasRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiver_))
            revert InvalidFeeReceiverManager();
        address oldFeeReceiver = feeReceiver;
        feeReceiver = payable(feeReceiver_);
        emit FeeReceiverUpdated(oldFeeReceiver, feeReceiver_);
    }

    /// @notice Forwards protocol fees held in treasury to the fee receiver
    /// @param commitId_ The ID of the commit whose fees are being sent
    /// @param amount_ The amount of fees to send
    /// @dev If transfer fails, emits FeeTransferFailure and leaves funds in treasury
    function _sendProtocolFees(uint256 commitId_, uint256 amount_) internal {
        if (amount_ == 0) return;
        if (feeReceiver == address(0)) return;

        (bool success, ) = feeReceiver.call{value: amount_}("");
        if (success) {
            treasuryBalance -= amount_;
        } else {
            emit FeeTransferFailure(
                commitId_,
                feeReceiver,
                amount_,
                hash(luckyBuys[commitId_])
            );
        }
    }
}
