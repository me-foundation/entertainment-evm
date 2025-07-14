// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LuckyBuy} from "./LuckyBuy.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";

contract LuckyBuyInitializable is LuckyBuy {
    bool private _initialized;

    error InitialOwnerCannotBeZero();
    error InitializableAlreadyInitialized();

    /// @dev Disables initializers for the implementation contract.
    constructor() LuckyBuy(0, 0, address(0x1), address(0x2), address(0x3)) {
        _initialized = true;
    }

    function initialize(
        address initialOwner_,
        uint256 protocolFee_,
        uint256 flatFee_,
        address feeReceiver_,
        address prng_,
        address feeReceiverManager_
    ) public {
        if (initialOwner_ == address(0)) revert InitialOwnerCannotBeZero();
        if (_initialized) revert InitializableAlreadyInitialized();

        _initialized = true;

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
