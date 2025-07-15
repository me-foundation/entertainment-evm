// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1155MInitializableV1_0_2} from "./common/interfaces/IERC1155MInitializableV1_0_2.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";
import {ISignatureVerifier} from "./common/interfaces/ISignatureVerifier.sol";
import {TokenRescuer} from "./common/TokenRescuer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title LuckyBuyCore
 * @dev Core business logic contract for LuckyBuy functionality
 * @dev This contract contains all shared business logic between LuckyBuy and LuckyBuyInitializable
 * @dev Designed to work with both upgradeable and non-upgradeable contexts
 */
contract LuckyBuyCore is TokenRescuer {
    // ############################################################
    // ############ STATE VARIABLES ############
    // ############################################################

    IPRNG public PRNG;
    address payable public feeReceiver;
    
    // Open Edition Token Configuration
    address public openEditionToken;
    uint256 public openEditionTokenId;
    uint32 public openEditionTokenAmount;

    // Core Data Storage
    ISignatureVerifier.CommitData[] public luckyBuys;
    mapping(bytes32 commitDigest => uint256 commitId) public commitIdByDigest;

    // Balance Tracking
    uint256 public treasuryBalance;
    uint256 public commitBalance;
    uint256 public protocolBalance;

    // Fee Configuration
    uint256 public maxReward;
    uint256 public protocolFee;
    uint256 public minReward;
    uint256 public flatFee;
    uint256 public bulkCommitFee;

    // Bulk Operations
    uint256 public maxBulkSize;
    uint256 public bulkSessionCounter;

    // Expiration Configuration
    uint256 public commitExpireTime;
    mapping(uint256 commitId => uint256 expiresAt) public commitExpiresAt;

    // Constants
    uint256 public constant MIN_COMMIT_EXPIRE_TIME = 1 minutes;
    uint256 public constant ONE_PERCENT = 100;
    uint256 public constant BASE_POINTS = 10000;

    // Role Constants
    bytes32 public constant FEE_RECEIVER_MANAGER_ROLE = keccak256("FEE_RECEIVER_MANAGER_ROLE");

    // State Tracking
    mapping(address cosigner => bool active) public isCosigner;
    mapping(address receiver => uint256 counter) public luckyBuyCount;
    mapping(uint256 commitId => bool fulfilled) public isFulfilled;
    mapping(uint256 commitId => bool expired) public isExpired;
    mapping(uint256 commitId => uint256 fee) public feesPaid;

    // ############################################################
    // ############ EVENTS ############
    // ############################################################

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
    event Withdrawal(address indexed sender, uint256 amount, address feeReceiver);
    event Deposit(address indexed sender, uint256 amount);
    event MinRewardUpdated(uint256 oldMinReward, uint256 newMinReward);
    event CommitExpireTimeUpdated(uint256 oldCommitExpireTime, uint256 newCommitExpireTime);
    event CommitExpired(uint256 indexed commitId, bytes32 digest);
    event OpenEditionTokenSet(address indexed token, uint256 indexed tokenId, uint256 amount);
    event FlatFeeUpdated(uint256 oldFlatFee, uint256 newFlatFee);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event OpenEditionContractTransferred(address indexed oldOwner, address indexed newOwner);
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
    event BulkCommitFeeUpdated(uint256 oldBulkCommitFee, uint256 newBulkCommitFee);
    event BulkCommit(
        address indexed sender,
        uint256 indexed bulkSessionId,
        uint256 numberOfCommits,
        uint256[] commitIds
    );

    // ############################################################
    // ############ ERRORS ############
    // ############################################################

    error AlreadyCosigner();
    error AlreadyFulfilled();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidCommitOwner();
    error InvalidCosigner();
    error InvalidOrderHash();
    error InvalidProtocolFee();
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
    error InvalidBulkCommitFee();
    error InvalidBulkSize();
    error InitialOwnerCannotBeZero();
    error NewImplementationCannotBeZero();

    // ############################################################
    // ############ STRUCTS ############
    // ############################################################

    struct CommitRequest {
        address receiver;
        address cosigner;
        uint256 seed;
        bytes32 orderHash;
        uint256 reward;
        uint256 amount;
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

    // ############################################################
    // ############ MODIFIERS ############
    // ############################################################

    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (
            luckyBuys[commitId_].receiver != msg.sender &&
            luckyBuys[commitId_].cosigner != msg.sender
        ) revert InvalidCommitOwner();
        _;
    }

    // ############################################################
    // ############ INITIALIZATION ############
    // ############################################################

    /**
     * @notice Initialize the core contract state
     * @dev This function is called by both constructor and initializer patterns
     * @dev Can be overridden by derived contracts for custom initialization
     */
    function _init(
        uint256 protocolFee_,
        uint256 flatFee_,
        uint256 bulkCommitFee_,
        address feeReceiver_,
        address prng_
    ) internal virtual {
        // Handle any existing balance
        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        // Set fee configuration
        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setBulkCommitFee(bulkCommitFee_);
        _setFeeReceiver(feeReceiver_);
        
        // Set PRNG
        PRNG = IPRNG(prng_);
        
        // Set default values
        maxBulkSize = 20;
        maxReward = 50 ether;
        minReward = BASE_POINTS;
        commitExpireTime = 1 days;
    }

    // ############################################################
    // ############ MAIN BUSINESS LOGIC ############
    // ############################################################

    /**
     * @notice Allows a user to commit funds for a chance to win
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        bytes32 orderHash_,
        uint256 reward_
    ) internal returns (uint256) {
        if (msg.value == 0) revert InvalidAmount();
        
        CommitRequest memory request = CommitRequest({
            receiver: receiver_,
            cosigner: cosigner_,
            seed: seed_,
            orderHash: orderHash_,
            reward: reward_,
            amount: msg.value
        });
        
        return _processCommit(request, protocolFee);
    }

    /**
     * @notice Allows a user to commit funds for multiple chances to win in a single transaction
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _bulkCommit(
        CommitRequest[] calldata requests_
    ) internal returns (uint256[] memory commitIds) {
        if (requests_.length == 0) revert InvalidAmount();
        if (requests_.length > maxBulkSize) revert InvalidBulkSize();
        
        uint256 effectiveFeeRate = protocolFee + bulkCommitFee;
        uint256 currentBulkSessionId = ++bulkSessionCounter;
        uint256 remainingValue = msg.value;
        
        commitIds = new uint256[](requests_.length);
        
        for (uint256 i = 0; i < requests_.length; i++) {
            CommitRequest calldata request = requests_[i];
            
            if (request.amount == 0 || remainingValue < request.amount) revert InvalidAmount();
            remainingValue -= request.amount;
            
            commitIds[i] = _processCommit(request, effectiveFeeRate, currentBulkSessionId);
        }
        if (remainingValue != 0) revert InvalidAmount();
        
        emit BulkCommit(msg.sender, currentBulkSessionId, requests_.length, commitIds);
        
        return commitIds;
    }

    /**
     * @notice Internal function to process a commit (individual or bulk)
     */
    function _processCommit(
        CommitRequest memory request_,
        uint256 feeRate_
    ) internal returns (uint256 commitId) {
        return _processCommit(request_, feeRate_, 0);
    }

    /**
     * @notice Internal function to process a commit (individual or bulk)
     */
    function _processCommit(
        CommitRequest memory request_,
        uint256 feeRate_,
        uint256 bulkSessionId_
    ) internal returns (uint256 commitId) {
        uint256 amountWithoutFlatFee = request_.amount - flatFee;
        uint256 commitAmount = calculateContributionWithoutFee(
            amountWithoutFlatFee,
            feeRate_
        );

        // All validations handled by _validateCommit
        _validateCommit(
            request_.receiver,
            request_.cosigner,
            request_.reward,
            commitAmount
        );

        // Handle flat fee payment
        _handleFlatFeePayment();

        // Calculate total fee amount (includes protocol fee + bulk fee for bulk commits)
        uint256 totalFeeAmount = amountWithoutFlatFee - commitAmount;

        // Create commit
        commitId = luckyBuys.length;
        uint256 userCounter = luckyBuyCount[request_.receiver]++;

        // Update balances
        feesPaid[commitId] = totalFeeAmount;
        protocolBalance += totalFeeAmount;
        commitBalance += commitAmount;

        // Store commit data
        ISignatureVerifier.CommitData memory commitData = ISignatureVerifier.CommitData({
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

        bytes32 digest = _hashCommitData(commitData);
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
            totalFeeAmount,
            flatFee,
            digest,
            bulkSessionId_
        );
    }

    /**
     * @notice Calculate contribution amount with custom fee rate
     */
    function calculateContributionWithoutFee(
        uint256 amount,
        uint256 feeRate
    ) public view returns (uint256) {
        return (amount * BASE_POINTS) / (BASE_POINTS + feeRate);
    }

    // ############################################################
    // ############ INTERNAL HELPER FUNCTIONS ############
    // ############################################################

    /**
     * @notice Internal function to handle flat fee payment
     */
    function _handleFlatFeePayment() internal {
        if (flatFee > 0 && feeReceiver != address(0)) {
            (bool success, ) = feeReceiver.call{value: flatFee}("");
            if (!success) revert TransferFailed();
        } else {
            treasuryBalance += flatFee;
        }
    }

    /**
     * @notice Deposits ETH into the treasury
     */
    function _depositTreasury(uint256 amount) internal {
        treasuryBalance += amount;
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Validates commit parameters
     */
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
        if (commitAmount < (reward_ / ONE_PERCENT) || commitAmount > reward_) {
            revert InvalidAmount();
        }
    }

    /**
     * @notice Hash commit data for signature verification
     * @dev This function should be overridden by derived contracts that implement ISignatureVerifier
     */
    function _hashCommitData(ISignatureVerifier.CommitData memory commitData) internal view virtual returns (bytes32) {
        // Default implementation - derived contracts should override this
        return keccak256(abi.encode(commitData));
    }

    /**
     * @notice Verify signature for commit data
     * @dev This function should be overridden by derived contracts that implement ISignatureVerifier
     */
    function _verifyCommitSignature(bytes32 digest, bytes calldata signature) internal view virtual returns (address) {
        // Default implementation - derived contracts should override this
        return address(0);
    }

    /**
     * @notice Hash order data
     * @dev This function should be overridden by derived contracts that implement ISignatureVerifier
     */
    function _hashOrder(
        address marketplace_,
        uint256 orderAmount_,
        bytes calldata orderData_,
        address token_,
        uint256 tokenId_
    ) internal view virtual returns (bytes32) {
        // Default implementation - derived contracts should override this
        return keccak256(abi.encode(marketplace_, orderAmount_, orderData_, token_, tokenId_));
    }

    // ############################################################
    // ############ SETTERS (INTERNAL) ############
    // ############################################################

    function _setProtocolFee(uint256 protocolFee_) internal {
        if (protocolFee_ > BASE_POINTS) revert InvalidProtocolFee();
        uint256 oldProtocolFee = protocolFee;
        protocolFee = protocolFee_;
        emit ProtocolFeeUpdated(oldProtocolFee, protocolFee_);
    }

    function _setFlatFee(uint256 flatFee_) internal {
        uint256 oldFlatFee = flatFee;
        flatFee = flatFee_;
        emit FlatFeeUpdated(oldFlatFee, flatFee_);
    }

    function _setBulkCommitFee(uint256 bulkCommitFee_) internal {
        if (bulkCommitFee_ > BASE_POINTS) revert InvalidBulkCommitFee();
        uint256 oldBulkCommitFee = bulkCommitFee;
        bulkCommitFee = bulkCommitFee_;
        emit BulkCommitFeeUpdated(oldBulkCommitFee, bulkCommitFee_);
    }

    function _setFeeReceiver(address feeReceiver_) internal {
        if (feeReceiver_ == address(0)) revert InvalidFeeReceiver();
        address oldFeeReceiver = feeReceiver;
        feeReceiver = payable(feeReceiver_);
        emit FeeReceiverUpdated(oldFeeReceiver, feeReceiver_);
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

    // ############################################################
    // ############ FULFILLMENT LOGIC ############
    // ############################################################

    /**
     * @notice Fulfills a commit with the result of the random number generation with fee splitting
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_,
        address feeSplitReceiver_,
        uint256 feeSplitPercentage_
    ) internal {
        // Validate fee split parameters if provided
        if (feeSplitReceiver_ != address(0) || feeSplitPercentage_ > 0) {
            if (feeSplitReceiver_ == address(0))
                revert InvalidFeeSplitReceiver();
            if (feeSplitReceiver_ == address(this))
                revert InvalidFeeSplitReceiver();
            if (feeSplitPercentage_ > BASE_POINTS)
                revert InvalidFeeSplitPercentage();
        }

        uint256 protocolFeesPaid = feesPaid[commitId_];

        _fulfillInternal(
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
            uint256 splitAmount = (protocolFeesPaid * feeSplitPercentage_) /
                BASE_POINTS;

            (bool success, ) = payable(feeSplitReceiver_).call{
                value: splitAmount
            }("");
            if (!success) {
                emit FeeTransferFailure(
                    commitId_,
                    feeSplitReceiver_,
                    splitAmount,
                    _hashCommitData(luckyBuys[commitId_])
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

    /**
     * @notice Internal fulfillment logic without fee splitting
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _fulfillInternal(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) internal {
        if (msg.value > 0) _depositTreasury(msg.value);

        (ISignatureVerifier.CommitData memory commitData, bytes32 digest) = _validateFulfillment(
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

    /**
     * @notice Fulfills multiple commits in a single transaction
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _bulkFulfill(
        FulfillRequest[] calldata requests_
    ) internal {
        if (requests_.length == 0) revert InvalidAmount();
        if (requests_.length > maxBulkSize) revert InvalidBulkSize();

        if (msg.value > 0) _depositTreasury(msg.value);

        // Process each fulfill individually
        for (uint256 i = 0; i < requests_.length; i++) {
            FulfillRequest calldata request = requests_[i];
            
            // Call the internal fulfill function with fee splitting
            _fulfill(
                commitIdByDigest[request.commitDigest],
                request.marketplace,
                request.orderData,
                request.orderAmount,
                request.token,
                request.tokenId,
                request.signature,
                request.feeSplitReceiver,
                request.feeSplitPercentage
            );
        }
    }

    /**
     * @notice Handles winning scenarios
     */
    function _handleWin(
        ISignatureVerifier.CommitData memory commitData,
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
            (bool transferSuccess, ) = commitData.receiver.call{value: orderAmount_}(
                ""
            );
            if (transferSuccess) {
                treasuryBalance -= orderAmount_;
            } else {
                emit TransferFailure(
                    commitData.id,
                    commitData.receiver,
                    orderAmount_,
                    digest
                );
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

    /**
     * @notice Validates fulfillment parameters
     */
    function _validateFulfillment(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) internal view returns (ISignatureVerifier.CommitData memory, bytes32) {
        if (commitId_ >= luckyBuys.length) revert InvalidCommitId();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isExpired[commitId_]) revert CommitIsExpired();

        ISignatureVerifier.CommitData memory commitData = luckyBuys[commitId_];

        if (
            commitData.orderHash !=
            _hashOrder(marketplace_, orderAmount_, orderData_, token_, tokenId_)
        ) revert InvalidOrderHash();

        if (orderAmount_ != commitData.reward) revert InvalidAmount();

        bytes32 digest = _hashCommitData(commitData);
        address cosigner = _verifyCommitSignature(digest, signature_);
        if (cosigner != commitData.cosigner || !isCosigner[cosigner]) {
            revert InvalidCosigner();
        }

        return (commitData, digest);
    }

    /**
     * @notice Calculates the odds of winning based on amount and reward
     */
    function _calculateOdds(
        uint256 amount,
        uint256 reward
    ) internal pure returns (uint256) {
        return (amount * BASE_POINTS) / reward;
    }

    /**
     * @notice Fulfills an order with the specified parameters
     */
    function _fulfillOrder(
        address to,
        bytes calldata data,
        uint256 amount
    ) internal returns (bool success) {
        (success, ) = to.call{value: amount}(data);
    }

    // ############################################################
    // ############ EXPIRATION LOGIC ############
    // ############################################################

    /**
     * @notice Allows the commit owner to expire a commit
     * @dev This function must be called from a contract that implements proper access control
     */
    function _expire(uint256 commitId_) internal {
        if (commitId_ >= luckyBuys.length) revert InvalidCommitId();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isExpired[commitId_]) revert CommitIsExpired();
        if (block.timestamp < commitExpiresAt[commitId_])
            revert CommitNotExpired();

        isExpired[commitId_] = true;

        ISignatureVerifier.CommitData memory commitData = luckyBuys[commitId_];

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
                _hashCommitData(commitData)
            );
        }

        emit CommitExpired(commitId_, _hashCommitData(commitData));
    }

    /**
     * @notice Allows bulk expiration of multiple commits
     * @dev This function must be called from a contract that implements proper access control
     */
    function _bulkExpire(uint256[] calldata commitIds_) internal {
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
    }

    // ############################################################
    // ############ WITHDRAWAL LOGIC ############
    // ############################################################

    /**
     * @notice Allows the admin to withdraw ETH from the contract balance
     * @dev This function must be called from a contract that implements proper access control
     */
    function _withdraw(uint256 amount) internal {
        if (amount > treasuryBalance) revert InsufficientBalance();
        treasuryBalance -= amount;

        (bool success, ) = payable(feeReceiver).call{value: amount}("");
        if (!success) revert WithdrawalFailed();

        emit Withdrawal(msg.sender, amount, feeReceiver);
    }

    /**
     * @notice Allows the admin to withdraw all ETH from the contract
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function _emergencyWithdraw() internal {
        treasuryBalance = 0;
        commitBalance = 0;
        protocolBalance = 0;

        uint256 currentBalance = address(this).balance;

        (bool success, ) = payable(feeReceiver).call{value: currentBalance}("");
        if (!success) revert WithdrawalFailed();

        emit Withdrawal(msg.sender, currentBalance, feeReceiver);
    }

    // ############################################################
    // ############ PROTOCOL FEE HANDLING ############
    // ############################################################

    /**
     * @notice Forwards protocol fees held in treasury to the fee receiver
     */
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
                _hashCommitData(luckyBuys[commitId_])
            );
        }
    }

    // ############################################################
    // ############ COSIGNER MANAGEMENT ############
    // ############################################################

    /**
     * @notice Adds a new authorized cosigner
     * @dev This function must be called from a contract that implements proper access control
     */
    function _addCosigner(address cosigner_) internal {
        if (cosigner_ == address(0)) revert InvalidCosigner();
        if (isCosigner[cosigner_]) revert AlreadyCosigner();
        isCosigner[cosigner_] = true;
        emit CosignerAdded(cosigner_);
    }

    /**
     * @notice Removes an authorized cosigner
     * @dev This function must be called from a contract that implements proper access control
     */
    function _removeCosigner(address cosigner_) internal {
        if (!isCosigner[cosigner_]) revert InvalidCosigner();
        isCosigner[cosigner_] = false;
        emit CosignerRemoved(cosigner_);
    }

    // ############################################################
    // ############ CONFIGURATION SETTERS ############
    // ############################################################

    function _setMaxReward(uint256 maxReward_) internal {
        if (maxReward_ < minReward) revert InvalidReward();
        uint256 oldMaxReward = maxReward;
        maxReward = maxReward_;
        emit MaxRewardUpdated(oldMaxReward, maxReward_);
    }

    function _setMinReward(uint256 minReward_) internal {
        if (minReward_ > maxReward) revert InvalidReward();
        if (minReward_ < BASE_POINTS) revert InvalidReward();
        uint256 oldMinReward = minReward;
        minReward = minReward_;
        emit MinRewardUpdated(oldMinReward, minReward_);
    }

    function _setCommitExpireTime(uint256 commitExpireTime_) internal {
        if (commitExpireTime_ < MIN_COMMIT_EXPIRE_TIME)
            revert InvalidCommitExpireTime();
        uint256 oldCommitExpireTime = commitExpireTime;
        commitExpireTime = commitExpireTime_;
        emit CommitExpireTimeUpdated(oldCommitExpireTime, commitExpireTime_);
    }

    function _setMaxBulkSize(uint256 maxBulkSize_) internal {
        if (maxBulkSize_ < 1) revert InvalidBulkSize();
        maxBulkSize = maxBulkSize_;
    }

    // ############################################################
    // ############ RECEIVE FUNCTION ############
    // ############################################################

    /**
     * @notice Handles receiving ETH
     */
    receive() external payable {
        _depositTreasury(msg.value);
    }

    // ############################################################
    // ############ PUBLIC INTERFACE FUNCTIONS ############
    // ############################################################

    /**
     * @notice Allows a user to commit funds for a chance to win
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        bytes32 orderHash_,
        uint256 reward_
    ) public payable virtual returns (uint256) {
        return _commit(receiver_, cosigner_, seed_, orderHash_, reward_);
    }

    /**
     * @notice Allows a user to commit funds for multiple chances to win in a single transaction
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function bulkCommit(
        CommitRequest[] calldata requests_
    ) public payable virtual returns (uint256[] memory) {
        return _bulkCommit(requests_);
    }

    /**
     * @notice Fulfills a commit with the result of the random number generation
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
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
    ) public payable virtual {
        _fulfill(
            commitId_,
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

    /**
     * @notice Fulfills a commit by digest with the result of the random number generation
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
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
    ) public payable virtual {
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

    /**
     * @notice Fulfills multiple commits in a single transaction
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function bulkFulfill(
        FulfillRequest[] calldata requests_
    ) public payable virtual {
        _bulkFulfill(requests_);
    }

    /**
     * @notice Allows the commit owner to expire a commit
     * @dev This function must be called from a contract that implements proper access control
     */
    function expire(uint256 commitId_) external virtual {
        _expire(commitId_);
    }

    /**
     * @notice Allows bulk expiration of multiple commits
     * @dev This function must be called from a contract that implements proper access control
     */
    function bulkExpire(uint256[] calldata commitIds_) external virtual {
        _bulkExpire(commitIds_);
    }

    /**
     * @notice Allows the admin to withdraw ETH from the contract balance
     * @dev This function must be called from a contract that implements proper access control
     */
    function withdraw(uint256 amount) external virtual {
        _withdraw(amount);
    }

    /**
     * @notice Allows the admin to withdraw all ETH from the contract
     * @dev This function must be called from a contract that implements proper access control and pausing
     */
    function emergencyWithdraw() external virtual {
        _emergencyWithdraw();
    }

    // ############################################################
    // ############ MANAGEMENT FUNCTIONS ############
    // ############################################################

    /**
     * @notice Sets the open edition token
     * @dev This function must be called from a contract that implements proper access control
     */
    function setOpenEditionToken(
        address token_,
        uint256 tokenId_,
        uint32 amount_
    ) external virtual {
        _setOpenEditionToken(token_, tokenId_, amount_);
    }

    /**
     * @notice Adds a new authorized cosigner
     * @dev This function must be called from a contract that implements proper access control
     */
    function addCosigner(address cosigner_) external virtual {
        _addCosigner(cosigner_);
    }

    /**
     * @notice Removes an authorized cosigner
     * @dev This function must be called from a contract that implements proper access control
     */
    function removeCosigner(address cosigner_) external virtual {
        _removeCosigner(cosigner_);
    }

    /**
     * @notice Sets the commit expire time
     * @dev This function must be called from a contract that implements proper access control
     */
    function setCommitExpireTime(uint256 commitExpireTime_) external virtual {
        _setCommitExpireTime(commitExpireTime_);
    }

    /**
     * @notice Sets the maximum allowed reward
     * @dev This function must be called from a contract that implements proper access control
     */
    function setMaxReward(uint256 maxReward_) external virtual {
        _setMaxReward(maxReward_);
    }

    /**
     * @notice Sets the minimum allowed reward
     * @dev This function must be called from a contract that implements proper access control
     */
    function setMinReward(uint256 minReward_) external virtual {
        _setMinReward(minReward_);
    }

    /**
     * @notice Sets the bulk commit fee
     * @dev This function must be called from a contract that implements proper access control
     */
    function setBulkCommitFee(uint256 bulkCommitFee_) external virtual {
        _setBulkCommitFee(bulkCommitFee_);
    }

    /**
     * @notice Sets the maximum bulk size
     * @dev This function must be called from a contract that implements proper access control
     */
    function setMaxBulkSize(uint256 maxBulkSize_) external virtual {
        _setMaxBulkSize(maxBulkSize_);
    }

    /**
     * @notice Pauses the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function pause() external virtual {
        // Override in derived contracts
    }

    /**
     * @notice Unpauses the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function unpause() external virtual {
        // Override in derived contracts
    }

    /**
     * @notice Sets the protocol fee
     * @dev This function must be called from a contract that implements proper access control
     */
    function setProtocolFee(uint256 protocolFee_) external virtual {
        _setProtocolFee(protocolFee_);
    }

    /**
     * @notice Sets the flat fee
     * @dev This function must be called from a contract that implements proper access control
     */
    function setFlatFee(uint256 flatFee_) external virtual {
        _setFlatFee(flatFee_);
    }

    /**
     * @notice Sets the fee receiver
     * @dev This function must be called from a contract that implements proper access control
     */
    function setFeeReceiver(address feeReceiver_) external virtual {
        _setFeeReceiver(feeReceiver_);
    }

    // ############################################################
    // ############ RESCUE FUNCTION PUBLIC INTERFACE ############
    // ############################################################

    /**
     * @notice Rescues an ERC20 token from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC20(
        address token,
        address to,
        uint256 amount
    ) external virtual {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        amounts[0] = amount;

        _rescueERC20Batch(tokens, tos, amounts);
    }

    /**
     * @notice Rescues an ERC721 token from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC721(
        address token,
        address to,
        uint256 tokenId
    ) external virtual {
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;

        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    /**
     * @notice Rescues an ERC1155 token from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC1155(
        address token,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external virtual {
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

    /**
     * @notice Rescues multiple ERC20 tokens from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC20Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata amounts
    ) external virtual {
        _rescueERC20Batch(tokens, tos, amounts);
    }

    /**
     * @notice Rescues multiple ERC721 tokens from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC721Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds
    ) external virtual {
        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    /**
     * @notice Rescues multiple ERC1155 tokens from the contract
     * @dev This function must be called from a contract that implements proper access control
     */
    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external virtual {
        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }

}