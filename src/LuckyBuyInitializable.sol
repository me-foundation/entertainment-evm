// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./LuckyBuyCore.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MEAccessControlUpgradeable} from "./common/MEAccessControlUpgradeable.sol";
import {SignatureVerifierUpgradeable} from "./common/SignatureVerifierUpgradeable.sol";

/**
 * @title LuckyBuyInitializable
 * @dev Upgradeable version of LuckyBuy contract using UUPS pattern
 * @dev Inherits ALL business logic from LuckyBuyCore
 * @dev This contract only handles infrastructure: access control, pausing, signature verification, upgrades, and reentrancy protection
 */
contract LuckyBuyInitializable is
    LuckyBuyCore,
    MEAccessControlUpgradeable,
    PausableUpgradeable,
    SignatureVerifierUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
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
        uint256 bulkCommitFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    ) public initializer {
        if (initialOwner_ == address(0)) revert InitialOwnerCannotBeZero();

        __MEAccessControl_init(initialOwner_);
        __Pausable_init();
        __SignatureVerifier_init("LuckyBuy", "1");
        __ReentrancyGuard_init();

        // Initialize core contract
        _init(protocolFee_, flatFee_, bulkCommitFee_, feeReceiver_, prng_);
        
        // Grant fee receiver manager role
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);
    }

    /// @dev Overriden to prevent unauthorized upgrades.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0))
            revert NewImplementationCannotBeZero();
    }

    // ############################################################
    // ############ ACCESS CONTROL OVERRIDES ############
    // ############################################################

    /**
     * @notice Override commit to add access control and pausing
     */
    function commit(
        address receiver_,
        address cosigner_,
        uint256 seed_,
        bytes32 orderHash_,
        uint256 reward_
    ) public payable override whenNotPaused returns (uint256) {
        return super.commit(receiver_, cosigner_, seed_, orderHash_, reward_);
    }

    /**
     * @notice Override bulkCommit to add access control and pausing
     */
    function bulkCommit(
        CommitRequest[] calldata requests_
    ) public payable override whenNotPaused returns (uint256[] memory) {
        return super.bulkCommit(requests_);
    }

    /**
     * @notice Override fulfill to add access control and pausing
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
    ) public payable override whenNotPaused {
        super.fulfill(commitId_, marketplace_, orderData_, orderAmount_, token_, tokenId_, signature_, feeSplitReceiver_, feeSplitPercentage_);
    }

    /**
     * @notice Override fulfillByDigest to add access control and pausing
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
    ) public payable override whenNotPaused {
        super.fulfillByDigest(commitDigest_, marketplace_, orderData_, orderAmount_, token_, tokenId_, signature_, feeSplitReceiver_, feeSplitPercentage_);
    }

    /**
     * @notice Override bulkFulfill to add access control and pausing
     */
    function bulkFulfill(
        FulfillRequest[] calldata requests_
    ) public payable override whenNotPaused {
        super.bulkFulfill(requests_);
    }

    /**
     * @notice Override expire to add access control and reentrancy protection
     */
    function expire(uint256 commitId_) external override onlyCommitOwnerOrCosigner(commitId_) nonReentrant {
        _expire(commitId_);
    }

    /**
     * @notice Override bulkExpire to add access control
     */
    function bulkExpire(uint256[] calldata commitIds_) external override {
        _bulkExpire(commitIds_);
    }

    /**
     * @notice Override withdraw to add access control and reentrancy protection
     */
    function withdraw(uint256 amount) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdraw(amount);
    }

    /**
     * @notice Override emergencyWithdraw to add access control and reentrancy protection
     */
    function emergencyWithdraw() external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _emergencyWithdraw();
        _pause();
    }

    // ############################################################
    // ############ MANAGEMENT FUNCTION OVERRIDES ############
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

    function setOpenEditionToken(
        address token_,
        uint256 tokenId_,
        uint32 amount_
    ) external override onlyRole(OPS_ROLE) {
        _setOpenEditionToken(token_, tokenId_, amount_);
    }

    function addCosigner(address cosigner_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _addCosigner(cosigner_);
    }

    function removeCosigner(address cosigner_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeCosigner(cosigner_);
    }

    function setCommitExpireTime(uint256 commitExpireTime_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setCommitExpireTime(commitExpireTime_);
    }

    function setMaxReward(uint256 maxReward_) external override onlyRole(OPS_ROLE) {
        _setMaxReward(maxReward_);
    }

    function setMinReward(uint256 minReward_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMinReward(minReward_);
    }

    function setBulkCommitFee(uint256 bulkCommitFee_) external override onlyRole(OPS_ROLE) {
        _setBulkCommitFee(bulkCommitFee_);
    }

    function setMaxBulkSize(uint256 maxBulkSize_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxBulkSize(maxBulkSize_);
    }

    function pause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setProtocolFee(uint256 protocolFee_) external override onlyRole(OPS_ROLE) {
        _setProtocolFee(protocolFee_);
    }

    function setFlatFee(uint256 flatFee_) external override onlyRole(OPS_ROLE) {
        _setFlatFee(flatFee_);
    }

    function transferFeeReceiverManager(
        address newFeeReceiverManager_
    ) external onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        if (newFeeReceiverManager_ == address(0))
            revert InvalidFeeReceiverManager();
        _revokeRole(FEE_RECEIVER_MANAGER_ROLE, msg.sender);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, newFeeReceiverManager_);
        emit FeeReceiverManagerTransferred(msg.sender, newFeeReceiverManager_);
    }

    function setFeeReceiver(address feeReceiver_) external override onlyRole(FEE_RECEIVER_MANAGER_ROLE) {
        if (feeReceiver_ == address(0)) revert InvalidFeeReceiver();
        if (hasRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiver_))
            revert InvalidFeeReceiverManager();
        _setFeeReceiver(feeReceiver_);
    }

    // ############################################################
    // ############ RESCUE FUNCTION OVERRIDES ############
    // ############################################################

    function rescueERC20(
        address token,
        address to,
        uint256 amount
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC20Batch(_toArray(token), _toArray(to), _toArray(amount));
    }

    function rescueERC721(
        address token,
        address to,
        uint256 tokenId
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC721Batch(_toArray(token), _toArray(to), _toArray(tokenId));
    }

    function rescueERC1155(
        address token,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC1155Batch(_toArray(token), _toArray(to), _toArray(tokenId), _toArray(amount));
    }

    function rescueERC20Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata amounts
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external override onlyRole(RESCUE_ROLE) {
        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }

    // Helper function to convert single values to arrays
    function _toArray(address value) private pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = value;
        return array;
    }

    function _toArray(uint256 value) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = value;
        return array;
    }

    // ############################################################
    // ############ VIRTUAL FUNCTION OVERRIDES ############
    // ############################################################

    /**
     * @notice Override hash function to use SignatureVerifier implementation
     */
    function _hashCommitData(ISignatureVerifier.CommitData memory commitData) internal view override returns (bytes32) {
        return hash(commitData);
    }

    /**
     * @notice Override signature verification to use SignatureVerifier implementation
     */
    function _verifyCommitSignature(bytes32 digest, bytes calldata signature) internal view override returns (address) {
        return _verifyDigest(digest, signature);
    }

    /**
     * @notice Override order hash function to use SignatureVerifier implementation
     */
    function _hashOrder(
        address marketplace_,
        uint256 orderAmount_,
        bytes calldata orderData_,
        address token_,
        uint256 tokenId_
    ) internal view override returns (bytes32) {
        return hashOrder(marketplace_, orderAmount_, orderData_, token_, tokenId_);
    }

    // ############################################################
    // ############ ERC1155 RECEIVER ############
    // ############################################################

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
    // ############ STORAGE GAP ############
    // ############################################################

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
}