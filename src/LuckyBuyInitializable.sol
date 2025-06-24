// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1155MInitializableV1_0_2} from "./common/interfaces/IERC1155MInitializableV1_0_2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MEAccessControlUpgradeable} from "./common/MEAccessControlUpgradeable.sol";
import {SignatureVerifierUpgradeable} from "./common/SignatureVerifierUpgradeable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";
import {TokenRescuer} from "./common/TokenRescuer.sol";


contract LuckyBuyInitializable is
    MEAccessControlUpgradeable,
    PausableUpgradeable,
    SignatureVerifierUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
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
    uint256 public maxReward;
    uint256 public protocolFee;
    uint256 public minReward;
    uint256 public flatFee;

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

    // Storage gap for future upgrades
    uint256[50] private __gap;

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
        bytes32 digest
    );
    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);
    event Fulfillment(
        address indexed sender,
        uint256 indexed commitId,
        uint256 rng,
        uint256 odds,
        bool win,
        address token,
        uint256 tokenId,
        uint256 amount,
        address receiver,
        uint256 fee,
        bytes32 digest
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
    error InitialOwnerCannotBeZero();
    error NewImplementationCannotBeZero();

    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (
            luckyBuys[commitId_].receiver != msg.sender &&
            luckyBuys[commitId_].cosigner != msg.sender
        ) revert InvalidCommitOwner();
        _;
    }

    /// @dev Disables initializers for the implementation contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and handles any pre-existing balance
    /// @dev Sets up EIP712 domain separator and deposits any ETH sent during deployment
    function initialize(
        address initialOwner_,
        uint256 protocolFee_,
        uint256 flatFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    ) public initializer {
        if (initialOwner_ == address(0)) revert InitialOwnerCannotBeZero();

        __MEAccessControl_init(initialOwner_);
        __Pausable_init();
        __SignatureVerifier_init("LuckyBuy", "1");
        __ReentrancyGuard_init();

        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setFeeReceiver(feeReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);
        
        // Initialize reward limits
        maxReward = 50 ether;
        minReward = BASE_POINTS;
    }

    /// @dev Overriden to prevent unauthorized upgrades.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert NewImplementationCannotBeZero();
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
        if (!isCosigner[cosigner_]) revert InvalidCosigner();
        if (cosigner_ == address(0)) revert InvalidCosigner();
        if (receiver_ == address(0)) revert InvalidReceiver();
        if (reward_ > maxReward) revert InvalidReward();
        if (reward_ < minReward) revert InvalidReward();
        if (reward_ == 0) revert InvalidReward();

        uint256 amountWithoutFlatFee = msg.value - flatFee;

        // We collect the flat fee regardless of the amount. It is not returned to the user, ever.
        treasuryBalance += flatFee;

        // This is the amount the user wants to commit
        uint256 commitAmount = calculateContributionWithoutFee(
            amountWithoutFlatFee
        );

        // The commit amount must be greater than one percent of the reward
        if (commitAmount < (reward_ / ONE_PERCENT)) revert InvalidAmount();

        // The fee is the amount without the flat fee minus the amount without the protocol fee
        uint256 protocolFee = amountWithoutFlatFee - commitAmount;

        // The commit amount must be less than the reward
        if (commitAmount > reward_) revert InvalidAmount();

        // Check if odds are greater than 100%
        if ((commitAmount * BASE_POINTS) / reward_ > BASE_POINTS)
            revert InvalidAmount();

        uint256 commitId = luckyBuys.length;
        uint256 userCounter = luckyBuyCount[receiver_]++;

        feesPaid[commitId] = protocolFee;
        protocolBalance += protocolFee;
        commitBalance += commitAmount;

        CommitData memory commitData = CommitData({
            id: commitId,
            receiver: receiver_,
            cosigner: cosigner_,
            seed: seed_,
            counter: userCounter,
            orderHash: orderHash_,
            amount: commitAmount,
            reward: reward_
        });

        luckyBuys.push(commitData);
        commitExpiresAt[commitId] = block.timestamp + commitExpireTime;

        bytes32 digest = hash(commitData);
        commitIdByDigest[digest] = commitId;

        emit Commit(
            msg.sender,
            commitId,
            receiver_,
            cosigner_,
            seed_,
            userCounter,
            orderHash_, // Relay tx properties: to, data, value
            commitAmount,
            reward_,
            protocolFee,
            flatFee,
            digest
        );

        return commitId;
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitId_ ID of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param signature_ Signature used for random number generation
    /// @dev Emits a Fulfillment event on success
    function fulfill(
        uint256 commitId_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) public payable whenNotPaused {
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

        _sendProtocolFees(commitId_, protocolFeesPaid);
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitId_ ID of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param signature_ Signature used for random number generation
    /// @param feeSplitReceiver_ Address of the fee split receiver
    /// @param feeSplitPercentage_ Percentage of the fee to split relative to the protocol fees paid
    /// @dev Emits a FeeSplit event on success
    function fulfillWithFeeSplit(
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
        if (feeSplitReceiver_ == address(0)) revert InvalidFeeSplitReceiver();
        if (feeSplitReceiver_ == address(this))
            revert InvalidFeeSplitReceiver();
        if (feeSplitPercentage_ > BASE_POINTS)
            revert InvalidFeeSplitPercentage();

        // Call fulfill as-is
        _fulfill(
            commitId_,
            marketplace_,
            orderData_,
            orderAmount_,
            token_,
            tokenId_,
            signature_
        );

        // All accounting is done in the fulfill function We will fetch to protocol fees that were transferred to the treasury and transfer the split amount from our treasury balance
        uint256 protocolFeesPaid = feesPaid[commitId_];
        uint256 splitAmount = (protocolFeesPaid * feeSplitPercentage_) /
            BASE_POINTS;

        (bool success, ) = payable(feeSplitReceiver_).call{value: splitAmount}(
            ""
        );

        // This is deliberate. We do not want to block execution and will manually send fees to the receiver.
        if (!success) {
            emit FeeTransferFailure(
                commitId_,
                feeSplitReceiver_,
                splitAmount,
                hash(luckyBuys[commitId_])
            );
        } else {
            // Subtract the split amount from the treasury balance
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
        // validate tx
        if (msg.value > 0) _depositTreasury(msg.value);
        if (orderAmount_ > treasuryBalance) revert InsufficientBalance();
        if (isFulfilled[commitId_]) revert AlreadyFulfilled();
        if (isExpired[commitId_]) revert CommitIsExpired();
        if (commitId_ >= luckyBuys.length) revert InvalidCommitId();

        // mark the commit as fulfilled
        isFulfilled[commitId_] = true;

        // validate commit data matches tx data
        CommitData memory commitData = luckyBuys[commitId_];

        // validate the order hash
        if (
            commitData.orderHash !=
            hashOrder(marketplace_, orderAmount_, orderData_, token_, tokenId_)
        ) revert InvalidOrderHash();

        // validate the reward amount
        if (orderAmount_ != commitData.reward) revert InvalidAmount();

        // hash commit, check signature. digest is needed later for logging
        bytes32 digest = hash(commitData);
        address cosigner = _verifyDigest(digest, signature_);
        if (cosigner != commitData.cosigner) revert InvalidCosigner();
        if (!isCosigner[cosigner]) revert InvalidCosigner();

        // Collect the commit balance and protocol fees
        // transfer the commit balance to the contract
        treasuryBalance += commitData.amount;
        commitBalance -= commitData.amount;

        // transfer the protocol fees to the contract
        uint256 protocolFeesPaid = feesPaid[commitData.id];

        treasuryBalance += protocolFeesPaid;
        protocolBalance -= protocolFeesPaid;

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
                digest
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
                msg.sender,
                commitId_,
                rng,
                odds,
                win,
                address(0),
                0,
                0,
                commitData.receiver,
                protocolFeesPaid,
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
    /// @param signature_ Signature used for random number generation
    /// @dev Emits a Fulfillment event on success
    function fulfillByDigest(
        bytes32 commitDigest_,
        address marketplace_,
        bytes calldata orderData_,
        uint256 orderAmount_,
        address token_,
        uint256 tokenId_,
        bytes calldata signature_
    ) public payable whenNotPaused {
        return
            fulfill(
                commitIdByDigest[commitDigest_],
                marketplace_,
                orderData_,
                orderAmount_,
                token_,
                tokenId_,
                signature_
            );
    }

    /// @notice Fulfills a commit with the result of the random number generation
    /// @param commitDigest_ Digest of the commit to fulfill
    /// @param marketplace_ Address where the order should be executed
    /// @param orderData_ Calldata for the order execution
    /// @param orderAmount_ Amount of ETH to send with the order
    /// @param token_ Address of the token being transferred (zero address for ETH)
    /// @param tokenId_ ID of the token if it's an NFT
    /// @param signature_ Signature used for random number generation
    /// @dev Emits a Fulfillment event on success
    function fulfillByDigestWithFeeSplit(
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
            fulfillWithFeeSplit(
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
        bytes32 digest
    ) internal {
        // execute the market data to transfer the nft
        bool success = _fulfillOrder(marketplace_, orderData_, orderAmount_);
        if (success) {
            // subtract the order amount from the contract balance
            treasuryBalance -= orderAmount_;
            // emit a success transfer for the nft
            emit Fulfillment(
                msg.sender,
                commitData.id,
                rng_,
                odds_,
                win_,
                token_,
                tokenId_,
                orderAmount_,
                commitData.receiver,
                protocolFeesPaid,
                digest
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
                msg.sender,
                commitData.id,
                rng_,
                odds_,
                win_,
                address(0),
                0,
                orderAmount_,
                commitData.receiver,
                protocolFeesPaid,
                digest
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

        (bool success, ) = payable(commitData.receiver).call{value: transferAmount}("");
        if (!success) {
            treasuryBalance += transferAmount;
            emit TransferFailure(commitId_, commitData.receiver, transferAmount, hash(commitData));
        }

        emit CommitExpired(commitId_, hash(commitData));
    }

    /// @notice Calculates contribution amount after removing fee
    /// @param amount The original amount including fee
    /// @return The contribution amount without the fee
    /// @dev Uses formula: contribution = (amount * FEE_DENOMINATOR) / (FEE_DENOMINATOR + feePercent)
    /// @dev This ensures fee isn't charged on the fee portion itself
    function calculateContributionWithoutFee(
        uint256 amount
    ) public view returns (uint256) {
        return (amount * BASE_POINTS) / (BASE_POINTS + protocolFee);
    }

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
