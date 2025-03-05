// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./common/MEAccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
contract LuckyBuy is MEAccessControl, Pausable {
    uint256 public balance;

    constructor() MEAccessControl() {
        uint256 existingBalance = address(this).balance;
        if (existingBalance > 0) {
            _depositTreasury(existingBalance);
        }
    }

    function _depositTreasury(uint256 amount) internal {
        balance += amount;
    }

    receive() external payable {
        _depositTreasury(msg.value);
    }
}
