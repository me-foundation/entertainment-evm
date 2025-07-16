// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LuckyBuy} from "./LuckyBuy.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";

contract LuckyBuyInitializable is LuckyBuy {
    error InitialOwnerCannotBeZero();

    /// @dev Disables initializers for the implementation contract.
    constructor() LuckyBuy(0, 0, address(0x1), address(0x2), address(0x3)) {
        _disableInitializers();
    }

    function initialize(
        address initialOwner_,
        uint256 protocolFee_,
        uint256 flatFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    ) public initializer {
        if (initialOwner_ == address(0)) revert InitialOwnerCannotBeZero();

        __ReentrancyGuard_init();
        __MEAccessControl_init();
        __Pausable_init();
        __SignatureVerifier_init("LuckyBuy", "1");

        maxReward = 50 ether;
        minReward = BASE_POINTS;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner_);
        _grantRole(OPS_ROLE, initialOwner_);
        _grantRole(RESCUE_ROLE, initialOwner_);

        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }

        _setProtocolFee(protocolFee_);
        _setFlatFee(flatFee_);
        _setFeeReceiver(feeReceiver_);
        PRNG = IPRNG(prng_);
        _grantRole(FEE_RECEIVER_MANAGER_ROLE, feeReceiverManager_);
    }
}
