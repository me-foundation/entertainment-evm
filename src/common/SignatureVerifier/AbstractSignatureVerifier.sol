// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

abstract contract AbstractSignatureVerifier is EIP712 {
    using ECDSA for bytes32;

    constructor(
        string memory name,
        string memory version
    ) EIP712(name, version) {}

    function _verify(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address) {
        return ECDSA.recover(digest, signature);
    }
}
