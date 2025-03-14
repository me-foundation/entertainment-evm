// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ISignatureVerifier.sol";

contract SignatureVerifier is ISignatureVerifier, EIP712 {
    using ECDSA for bytes32;

    constructor(
        string memory name,
        string memory version
    ) EIP712(name, version) {}

    function hashOrder(
        address txTo_,
        bytes memory data_,
        uint256 amount_,
        address token_,
        uint256 tokenId_
    ) public view returns (bytes32) {
        return _hashOrder(txTo_, data_, amount_, token_, tokenId_);
    }

    function _hashOrder(
        address txTo_,
        bytes memory data_,
        uint256 amount_,
        address token_,
        uint256 tokenId_
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(txTo_, data_, amount_, token_, tokenId_));
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
                            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,string orderHash,uint256 amount,uint256 reward)"
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
        return ECDSA.recover(digest, signature);
    }
}
