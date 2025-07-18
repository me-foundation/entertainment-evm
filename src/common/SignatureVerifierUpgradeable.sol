// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ISignatureVerifier.sol";

abstract contract SignatureVerifierUpgradeable is ISignatureVerifier, EIP712Upgradeable {
    using ECDSA for bytes32;

    function __SignatureVerifier_init(
        string memory name,
        string memory version
    ) internal {
        __EIP712_init(name, version);
    }

    function hashOrder(
        address to,
        uint256 value,
        bytes memory data,
        address tokenAddress,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(to, value, data, tokenAddress, tokenId));
    }

    /// @notice Hashes a commit
    /// @param commit Commit to hash
    /// @return Hash of the commit
    function hash(CommitData memory commit) public view returns (bytes32) {
        return _hash(commit);
    }

    /// @dev Internal function to hash a commit
    /// @param commit Commit to hash
    /// @return Hash of the commit
    function _hash(CommitData memory commit) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,bytes32 orderHash,uint256 amount,uint256 reward)"
                        ),
                        commit.id,
                        commit.receiver,
                        commit.cosigner,
                        commit.seed,
                        commit.counter,
                        commit.orderHash,
                        commit.amount,
                        commit.reward
                    )
                )
            );
    }

    /// @notice Verifies the signature for a given Commit, returning the address of the signer.
    /// @dev Will revert if the signature is invalid. Does not verify that the signer is authorized to mint NFTs.
    /// @param commit A commit.
    /// @param signature An EIP712 signature of the given commit.
    function verify(
        CommitData memory commit,
        bytes memory signature
    ) public view returns (address) {
        return _verify(commit, signature);
    }

    /// @dev Internal function to verify a commit
    /// @param commit Commit to verify
    /// @param signature Signature to verify
    /// @return Address of the signer
    function _verify(
        CommitData memory commit,
        bytes memory signature
    ) internal view returns (address) {
        bytes32 digest = _hash(commit);
        return _verifyDigest(digest, signature);
    }
    /// @dev Internal function to verify a commit. Expects _hash(commit) elsewhere.
    /// @param signature Signature to verify
    /// @return Address of the signer
    function _verifyDigest(
        bytes32 digest,
        bytes memory signature
    ) internal view returns (address) {
        return ECDSA.recover(digest, signature);
    }
}