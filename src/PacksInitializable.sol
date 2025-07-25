// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Packs} from "./Packs.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";

contract PacksInitializable is Packs, UUPSUpgradeable {
    error InvalidZeroAddress();

    /// @dev Disables initializers for the implementation contract.
    constructor() Packs(address(0x2), address(0x3), address(0x4)) {
        _disableInitializers();
    }

    /// @notice Initializes the contract and handles any pre-existing balance
    /// @dev Sets up EIP712 domain separator and deposits any ETH sent during deployment
    function initialize(
        address initialOwner_,
        address fundsReceiver_,
        address prng_,
        address fundsReceiverManager_
    ) public initializer {
        if (initialOwner_ == address(0)) revert InvalidZeroAddress();

        __ReentrancyGuard_init();
        __MEAccessControl_init();
        __Pausable_init();
        __PacksSignatureVerifier_init("Packs", "1");

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

        // Grant roles to initial owner
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner_);
        _grantRole(OPS_ROLE, initialOwner_);
        _grantRole(RESCUE_ROLE, initialOwner_);
    }

    /// @dev Overriden to prevent unauthorized upgrades.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0))
            revert InvalidZeroAddress();
    }
}