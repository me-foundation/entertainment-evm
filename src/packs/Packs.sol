// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Errors} from "../common/Errors.sol";

import "./base/PacksCommit.sol";
import "./base/PacksFulfill.sol";
import "./base/PacksAdmin.sol";

contract Packs is
    PacksAdmin,
    PacksCommit,
    PacksFulfill
{
    // ============================================================
    // MODIFIERS
    // ============================================================
    
    modifier onlyCommitOwnerOrCosigner(uint256 commitId_) {
        if (packs[commitId_].receiver != msg.sender && packs[commitId_].cosigner != msg.sender) {
            revert Errors.InvalidCommitOwner();
        }
        _;
    }

    // ============================================================
    // CONSTRUCTOR
    // ============================================================

    constructor(uint256 protocolFee_,uint256 flatFee_,address fundsReceiver_, address prng_, address fundsReceiverManager_) initializer {
        __MEAccessControl_init();
        __Pausable_init();
        __PacksSignatureVerifier_init("Packs", "1");
        __ReentrancyGuard_init();

        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setFundsReceiver(fundsReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FUNDS_RECEIVER_MANAGER_ROLE, fundsReceiverManager_);

        // Initialize reward limits
        minReward = 0.01 ether;
        maxReward = 5 ether;

        minPackPrice = 0.01 ether;
        maxPackPrice = 0.25 ether;

        // Initialize expiries
        commitCancellableTime = 1 hours;
        nftFulfillmentExpiryTime = 10 minutes;
    }

    // ============================================================
    // CORE BUSINESS LOGIC
    // ============================================================

    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        PackType packType_,
        BucketData[] memory buckets_,
        bytes memory signature_
    ) external payable whenNotPaused returns (uint256) {
        uint256 packPrice = _validateAndCalculatePackPrice(msg.value);
        return _commit(receiver_, cosigner_, seed_, packType_, buckets_, signature_, packPrice, msg.value);
    }

    /// @notice Commit to a pack using a request struct
    /// @param commitRequest_ The commit request containing all parameters
    /// @return The commit ID
    function commit(
        CommitRequest calldata commitRequest_
    ) external payable whenNotPaused returns (uint256) {
        uint256 packPrice = _validateAndCalculatePackPrice(msg.value);
        return _commit(
            commitRequest_.receiver,
            commitRequest_.cosigner,
            commitRequest_.seed,
            commitRequest_.packType,
            commitRequest_.buckets,
            commitRequest_.signature,
            packPrice,
            msg.value
        );
    }

    function commitBatch(
        CommitRequest[] calldata commitRequests_
    ) external payable whenNotPaused returns (uint256[] memory) {
        return _commitBatch(commitRequests_);
    }

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
        FulfillmentOption choice_
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
            choice_
        );
    }

    /// @notice Fulfill a pack using a request struct with digest
    /// @param fulfillRequest_ The fulfill request containing digest and all parameters
    function fulfill(
        FulfillRequest calldata fulfillRequest_
    ) external payable whenNotPaused {
        _fulfill(
            commitIdByDigest[fulfillRequest_.digest],
            fulfillRequest_.marketplace,
            fulfillRequest_.orderData,
            fulfillRequest_.orderAmount,
            fulfillRequest_.token,
            fulfillRequest_.tokenId,
            fulfillRequest_.payoutAmount,
            fulfillRequest_.commitSignature,
            fulfillRequest_.fulfillmentSignature,
            fulfillRequest_.choice
        );
    }

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
        FulfillmentOption choice_
    ) external payable whenNotPaused {
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
            choice_
        );
    }

    function fulfillBatch(
        FulfillRequest[] calldata fulfillRequests_
    ) external payable whenNotPaused {
        _fulfillBatch(fulfillRequests_);
    }

    function cancel(uint256 commitId_) external nonReentrant onlyCommitOwnerOrCosigner(commitId_) {
        _cancel(commitId_);
    }

    // ============================================================
    // TREASURY MANAGEMENT
    // ============================================================

    function withdrawTreasury(uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdrawTreasury(amount);
    }

    function emergencyWithdraw() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _emergencyWithdraw();
    }

    receive() external payable {
        _depositTreasury(msg.value);
    }

    // ============================================================
    // ADMIN CONFIGURATION
    // ============================================================

    function addCosigner(address cosigner_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCosigner(cosigner_);
    }

    function removeCosigner(address cosigner_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeCosigner(cosigner_);
    }

    function setCommitCancellableTime(uint256 commitCancellableTime_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateCommitCancellableTime(commitCancellableTime_);
    }

    function setNftFulfillmentExpiryTime(uint256 nftFulfillmentExpiryTime_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateNftFulfillmentExpiryTime(nftFulfillmentExpiryTime_);
    }

    function setMinReward(uint256 minReward_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateMinReward(minReward_);
    }

    function setMaxReward(uint256 maxReward_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateMaxReward(maxReward_);
    }

    function setMinPackPrice(uint256 minPackPrice_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateMinPackPrice(minPackPrice_);
    }

    function setMaxPackPrice(uint256 maxPackPrice_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateMaxPackPrice(maxPackPrice_);
    }

    function setProtocolFee(uint256 protocolFee_) external onlyRole(OPS_ROLE) {
        _setProtocolFee(protocolFee_);
    }

    function setFlatFee(uint256 flatFee_) external onlyRole(OPS_ROLE) {
        _setFlatFee(flatFee_);
    }

    function setFundsReceiver(address fundsReceiver_) external onlyRole(FUNDS_RECEIVER_MANAGER_ROLE) {
        _setFundsReceiver(fundsReceiver_);
    }

    function transferFundsReceiverManager(address newFundsReceiverManager_)
        external
        onlyRole(FUNDS_RECEIVER_MANAGER_ROLE)
    {
        if (newFundsReceiverManager_ == address(0)) {
            revert Errors.InvalidFundsReceiverManager();
        }
        _transferFundsReceiverManager(newFundsReceiverManager_);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============================================================
    // VIEW FUNCTIONS & UTILITIES
    // ============================================================

    function getPacksLength() external view returns (uint256) {
        return packs.length;
    }
    
    // ============================================================
    // INTERNAL OVERRIDES
    // ============================================================

    function _transferFundsReceiverManager(address newFundsReceiverManager_) internal override {
        _revokeRole(FUNDS_RECEIVER_MANAGER_ROLE, msg.sender);
        _grantRole(FUNDS_RECEIVER_MANAGER_ROLE, newFundsReceiverManager_);
        emit FundsReceiverManagerTransferred(msg.sender, newFundsReceiverManager_);
    }
}
