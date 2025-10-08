// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./PacksStorage.sol";
import {MEAccessControlUpgradeable} from "../../common/MEAccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Errors} from "../../common/Errors.sol";
import {TokenRescuer} from "../../common/TokenRescuer.sol";

/// @title PacksAdmin
/// @notice Handles admin configuration, treasury management, pause controls, and token rescue for Packs contract
/// @dev Abstract contract with admin helpers - storage accessed from PacksStorage
abstract contract PacksAdmin is MEAccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, PacksStorage, TokenRescuer {
    
    // ============================================================
    // EVENTS
    // ============================================================
    
    event CosignerAdded(address indexed cosigner);
    event CosignerRemoved(address indexed cosigner);
    event MaxRewardUpdated(uint256 oldMaxReward, uint256 newMaxReward);
    event MaxPackPriceUpdated(uint256 oldMaxPackPrice, uint256 newMaxPackPrice);
    event MinRewardUpdated(uint256 oldMinReward, uint256 newMinReward);
    event MinPackPriceUpdated(uint256 oldMinPackPrice, uint256 newMinPackPrice);
    event CommitCancellableTimeUpdated(uint256 oldCommitCancellableTime, uint256 newCommitCancellableTime);
    event NftFulfillmentExpiryTimeUpdated(uint256 oldNftFulfillmentExpiryTime, uint256 newNftFulfillmentExpiryTime);
    event FundsReceiverUpdated(address indexed oldFundsReceiver, address indexed newFundsReceiver);
    event FundsReceiverManagerTransferred(
        address indexed oldFundsReceiverManager, address indexed newFundsReceiverManager
    );
    event MinPackRewardMultiplierUpdated(uint256 oldMinPackRewardMultiplier, uint256 newMinPackRewardMultiplier);
    event MaxPackRewardMultiplierUpdated(uint256 oldMaxPackRewardMultiplier, uint256 newMaxPackRewardMultiplier);
    event ProtocolFeeUpdated(uint256 oldProtocolFee, uint256 newProtocolFee);
    event FlatFeeUpdated(uint256 oldFlatFee, uint256 newFlatFee);
    event TreasuryWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    event EmergencyWithdrawal(address indexed sender, uint256 amount, address fundsReceiver);
    
    // ============================================================
    // ADMIN CONFIGURATION
    // ============================================================
    
    // ---------- Cosigner Management ----------
    
    function _addCosigner(address cosigner_) internal {
        if (cosigner_ == address(0)) revert Errors.CosignerAddressZero();
        if (isCosigner[cosigner_]) revert Errors.AlreadyCosigner();
        isCosigner[cosigner_] = true;
        emit CosignerAdded(cosigner_);
    }
    
    function _removeCosigner(address cosigner_) internal {
        if (!isCosigner[cosigner_]) revert Errors.NotActiveCosigner();
        isCosigner[cosigner_] = false;
        emit CosignerRemoved(cosigner_);
    }
    
    // ---------- Time Parameters ----------
    
    function _updateCommitCancellableTime(uint256 commitCancellableTime_) internal {
        if (commitCancellableTime_ < MIN_COMMIT_CANCELLABLE_TIME) {
            revert Errors.InvalidCommitCancellableTime();
        }
        uint256 oldCommitCancellableTime = commitCancellableTime;
        commitCancellableTime = commitCancellableTime_;
        emit CommitCancellableTimeUpdated(oldCommitCancellableTime, commitCancellableTime_);
    }
    
    function _updateNftFulfillmentExpiryTime(uint256 nftFulfillmentExpiryTime_) internal {
        if (nftFulfillmentExpiryTime_ < MIN_NFT_FULFILLMENT_EXPIRY_TIME) {
            revert Errors.InvalidNftFulfillmentExpiryTime();
        }
        uint256 oldNftFulfillmentExpiryTime = nftFulfillmentExpiryTime;
        nftFulfillmentExpiryTime = nftFulfillmentExpiryTime_;
        emit NftFulfillmentExpiryTimeUpdated(oldNftFulfillmentExpiryTime, nftFulfillmentExpiryTime_);
    }
    
    // ---------- Reward Limits ----------
    
    function _updateMinReward(uint256 minReward_) internal {
        if (minReward_ == 0) revert Errors.InvalidReward();
        if (minReward_ > maxReward) revert Errors.InvalidReward();
        uint256 oldMinReward = minReward;
        minReward = minReward_;
        emit MinRewardUpdated(oldMinReward, minReward_);
    }
    
    function _updateMaxReward(uint256 maxReward_) internal {
        if (maxReward_ == 0) revert Errors.InvalidReward();
        if (maxReward_ < minReward) revert Errors.InvalidReward();
        uint256 oldMaxReward = maxReward;
        maxReward = maxReward_;
        emit MaxRewardUpdated(oldMaxReward, maxReward_);
    }
    
    // ---------- Pack Price Limits ----------
    
    function _updateMinPackPrice(uint256 minPackPrice_) internal {
        if (minPackPrice_ == 0) revert Errors.InvalidPackPrice();
        if (minPackPrice_ > maxPackPrice) revert Errors.InvalidPackPrice();
        uint256 oldMinPackPrice = minPackPrice;
        minPackPrice = minPackPrice_;
        emit MinPackPriceUpdated(oldMinPackPrice, minPackPrice_);
    }
    
    function _updateMaxPackPrice(uint256 maxPackPrice_) internal {
        if (maxPackPrice_ == 0) revert Errors.InvalidPackPrice();
        if (maxPackPrice_ < minPackPrice) revert Errors.InvalidPackPrice();
        uint256 oldMaxPackPrice = maxPackPrice;
        maxPackPrice = maxPackPrice_;
        emit MaxPackPriceUpdated(oldMaxPackPrice, maxPackPrice_);
    }
    
    // ---------- Multipliers ----------
    
    function _updateMinPackRewardMultiplier(uint256 minPackRewardMultiplier_) internal {
        if (minPackRewardMultiplier_ == 0) revert Errors.InvalidPackRewardMultiplier();
        if (minPackRewardMultiplier_ > maxPackRewardMultiplier) revert Errors.InvalidPackRewardMultiplier();
        uint256 oldMinPackRewardMultiplier = minPackRewardMultiplier;
        minPackRewardMultiplier = minPackRewardMultiplier_;
        emit MinPackRewardMultiplierUpdated(oldMinPackRewardMultiplier, minPackRewardMultiplier_);
    }
    
    function _updateMaxPackRewardMultiplier(uint256 maxPackRewardMultiplier_) internal {
        if (maxPackRewardMultiplier_ == 0) revert Errors.InvalidPackRewardMultiplier();
        if (maxPackRewardMultiplier_ < minPackRewardMultiplier) revert Errors.InvalidPackRewardMultiplier();
        uint256 oldMaxPackRewardMultiplier = maxPackRewardMultiplier;
        maxPackRewardMultiplier = maxPackRewardMultiplier_;
        emit MaxPackRewardMultiplierUpdated(oldMaxPackRewardMultiplier, maxPackRewardMultiplier_);
    }
    
    // ---------- Fees ----------
    
    function _setProtocolFee(uint256 protocolFee_) internal {
        if (protocolFee_ > BASE_POINTS) revert Errors.InvalidProtocolFee();
        uint256 oldProtocolFee = protocolFee;
        protocolFee = protocolFee_;
        emit ProtocolFeeUpdated(oldProtocolFee, protocolFee_);
    }
    
    function _setFlatFee(uint256 flatFee_) internal {
        uint256 oldFlatFee = flatFee;
        flatFee = flatFee_;
        emit FlatFeeUpdated(oldFlatFee, flatFee_);
    }
    
    // ---------- Funds Receiver ----------
    
    function _setFundsReceiver(address fundsReceiver_) internal virtual {
        if (fundsReceiver_ == address(0)) revert Errors.FundsReceiverAddressZero();
        if (hasRole(FUNDS_RECEIVER_MANAGER_ROLE, fundsReceiver_)) {
            revert Errors.InvalidFundsReceiverManager();
        }
        address oldFundsReceiver = fundsReceiver;
        fundsReceiver = payable(fundsReceiver_);
        emit FundsReceiverUpdated(oldFundsReceiver, fundsReceiver_);
    }

      // ============================================================
    // TREASURY LOGIC
    // ============================================================
    
    function _withdrawTreasury(uint256 amount) internal {
        if (amount == 0) revert Errors.WithdrawAmountZero();
        if (amount > treasuryBalance) revert Errors.WithdrawAmountExceedsTreasury();
        treasuryBalance -= amount;

        (bool success,) = payable(fundsReceiver).call{value: amount}("");
        if (!success) revert Errors.WithdrawalFailed();

        emit TreasuryWithdrawal(msg.sender, amount, fundsReceiver);
    }
    
    function _emergencyWithdraw() internal virtual {
        treasuryBalance = 0;
        commitBalance = 0;
        protocolBalance = 0;

        uint256 currentBalance = address(this).balance;
        _rescueETH(fundsReceiver, currentBalance);
        // Pause must be called by inheriting contract that has PausableUpgradeable
        _pause();
        emit EmergencyWithdrawal(msg.sender, currentBalance, fundsReceiver);
    }
    
    
    function _transferFundsReceiverManager(address newFundsReceiverManager_) internal virtual;
    
    // ============================================================
    // RESCUE FUNCTIONS (Token Recovery)
    // ============================================================

    function rescueERC20(address token, address to, uint256 amount) external {
        _checkRole(RESCUE_ROLE, msg.sender);
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        amounts[0] = amount;

        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721(address token, address to, uint256 tokenId) external {
        _checkRole(RESCUE_ROLE, msg.sender);
        address[] memory tokens = new address[](1);
        address[] memory tos = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        tokens[0] = token;
        tos[0] = to;
        tokenIds[0] = tokenId;

        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155(address token, address to, uint256 tokenId, uint256 amount) external {
        _checkRole(RESCUE_ROLE, msg.sender);
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
    {
        _checkRole(RESCUE_ROLE, msg.sender);
        _rescueERC20Batch(tokens, tos, amounts);
    }

    function rescueERC721Batch(address[] calldata tokens, address[] calldata tos, uint256[] calldata tokenIds)
        external
    {
        _checkRole(RESCUE_ROLE, msg.sender);
        _rescueERC721Batch(tokens, tos, tokenIds);
    }

    function rescueERC1155Batch(
        address[] calldata tokens,
        address[] calldata tos,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external {
        _checkRole(RESCUE_ROLE, msg.sender);
        _rescueERC1155Batch(tokens, tos, tokenIds, amounts);
    }
}
