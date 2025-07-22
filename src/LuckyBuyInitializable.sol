// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LuckyBuy} from "./LuckyBuy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";

contract LuckyBuyInitializable is LuckyBuy, UUPSUpgradeable {
    error InvalidZeroAddress();

    /// @dev Disables initializers for the implementation contract.
    constructor() LuckyBuy(0, 0, 0, address(0x1), address(0x2), address(0x3)) {
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
        if (initialOwner_ == address(0)) revert InvalidZeroAddress();

        __ReentrancyGuard_init();
        __MEAccessControl_init();
        __Pausable_init();
        __LuckyBuySignatureVerifier_init("LuckyBuy", "1");

        maxReward = 50 ether;
        minReward = BASE_POINTS;
        maxBulkSize = 20;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner_);
        _grantRole(OPS_ROLE, initialOwner_);
        _grantRole(RESCUE_ROLE, initialOwner_);

        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setBulkCommitFee(bulkCommitFee_);
        _setFeeReceiver(feeReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);
    }

    /// @dev Overriden to prevent unauthorized upgrades.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0))
            revert InvalidZeroAddress();
    }
}