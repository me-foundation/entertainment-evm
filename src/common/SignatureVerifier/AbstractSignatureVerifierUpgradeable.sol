// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract AbstractSignatureVerifierUpgradeable is EIP712Upgradeable {
    using ECDSA for bytes32;

    function __AbstractSignatureVerifier_init(
        string memory name,
        string memory version
    ) internal onlyInitializing {
        __EIP712_init(name, version);
    }

    function _verify(
        bytes32 digest,
        bytes memory signature
    ) internal view virtual returns (address) {
        return ECDSA.recover(digest, signature);
    }

    function verify(
        bytes32 digest,
        bytes memory signature
    ) public view virtual returns (address) {
        return _verify(digest, signature);
    }
}