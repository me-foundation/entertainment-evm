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

    /// @notice Hashes the typed data
    /// @dev Must be implemented by the inheriting contract for specific data types
    function _hashTyped(
        bytes memory encodedStruct
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(encodedStruct));
    }

    function _verifyDigest(
        bytes32 digest,
        bytes memory signature
    ) internal pure virtual returns (address) {
        return ECDSA.recover(digest, signature);
    }

    function _verify(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address) {
        return _verifyDigest(digest, signature);
    }
}
