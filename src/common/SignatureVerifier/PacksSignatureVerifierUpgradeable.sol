// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./AbstractSignatureVerifierUpgradeable.sol";

contract PacksSignatureVerifierUpgradeable is
    AbstractSignatureVerifierUpgradeable
{
    struct BucketData {
        uint256 oddsBps;
        uint256 minValue;
        uint256 maxValue;
    }

    struct CommitData {
        uint256 id;
        address receiver;
        address cosigner;
        uint256 seed;
        uint256 counter;
        uint256 packPrice;
        BucketData[] buckets;
        bytes32 packHash;
    }

    enum PackType {
        NFT,
        RWA
    }

    enum FulfillmentOption {
        NFT,
        Payout
    }

    bytes32 private constant _TYPE_HASH =
        keccak256(
            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,uint256 packPrice,BucketData[] buckets,bytes32 packHash)"
        );

    function __PacksSignatureVerifier_init(
        string memory name,
        string memory version
    ) internal onlyInitializing {
        __AbstractSignatureVerifier_init(name, version);
    }

    /// @notice Hashes a commit
    /// @param commit Commit to hash
    /// @return Hash of the commit
    function hashCommit(CommitData memory commit) public view returns (bytes32) {
        return _hashCommit(commit);
    }

    /// @dev Internal function to hash a commit
    /// @param commit Commit to hash
    /// @return Hash of the commit
    function _hashCommit(CommitData memory commit) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,uint256 packPrice,BucketData[] buckets,bytes32 packHash)"
                    ),
                    commit.id,
                    commit.receiver,
                    commit.cosigner,
                    commit.seed,
                    commit.counter,
                    commit.packPrice,
                    commit.buckets,
                    commit.packHash
                )
            )
        );
    }

    /// @notice Hashes a pack commit
    /// @param packType Pack type
    /// @param packPrice Pack price in ether
    /// @param buckets Buckets used in the pack
    /// @return Hash of the pack
    function hashPack(PackType packType, uint256 packPrice, BucketData[] memory buckets) public pure returns (bytes32) {
        return keccak256(abi.encode(packType, packPrice, buckets));
    }

    /// @notice Hashes a fulfillment
    /// @param digest The commit digest
    /// @param marketplace Marketplace address
    /// @param orderAmount Order amount
    /// @param orderData Order data
    /// @param token Token address
    /// @param tokenId Token id
    /// @param payoutAmount ETH value on payout
    /// @param choice The receiver's choice
    /// @return Hash of the fulfillment
    function hashFulfillment(
        bytes32 digest,
        address marketplace,
        uint256 orderAmount,
        bytes memory orderData,
        address token,
        uint256 tokenId,
        uint256 payoutAmount,
        FulfillmentOption choice
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(digest, marketplace, orderAmount, orderData, token, tokenId, payoutAmount, choice));
    }

    /// @notice Verifies the signature for a given Commit, returning the address of the signer.
    /// @dev Will revert if the signature is invalid. Does not verify that the signer is authorized to mint NFTs.
    /// @param commit A commit.
    /// @param signature An EIP712 signature of the given commit.
    function verifyCommit(CommitData memory commit, bytes memory signature) public view returns (address) {
        return _verifyCommit(commit, signature);
    }

    /// @dev Internal function to verify a commit
    /// @param commit Commit to verify
    /// @param signature Signature to verify
    /// @return Address of the signer
    function _verifyCommit(CommitData memory commit, bytes memory signature) internal view returns (address) {
        bytes32 digest = _hashCommit(commit);
        return _verifyHash(digest, signature);
    }

    /// @notice Verifies the signature for a given hash, returning the address of the signer.
    /// @dev Will revert if the signature is invalid. Does not verify that the signer is authorized to mint NFTs.
    /// @param hash A hash.
    /// @param signature An EIP712 signature of the given hash.
    function verifyHash(bytes32 hash, bytes memory signature) public pure returns (address) {
        return _verifyHash(hash, signature);
    }

    /// @dev Internal function to verify a hash
    /// @param hash Hash to verify
    /// @param signature Signature to verify
    /// @return Address of the signer
    function _verifyHash(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(hash, signature);
    }
}
