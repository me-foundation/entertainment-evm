// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPacksSignatureVerifier {
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
        uint256 payoutBps;
        BucketData[] buckets;
        bytes32 packHash;
    }

    enum FulfillmentOption {
        Payout,
        NFT 

    }

    function hashCommit(CommitData memory commit) external view returns (bytes32);

    function hashPack(uint256 packPrice, BucketData[] memory buckets) external pure returns (bytes32);

    function hashOrder(address to, uint256 value, bytes memory data, address tokenAddress, uint256 tokenId)
        external
        pure
        returns (bytes32);

    function hashChoice(bytes32 digest, FulfillmentOption choice) external pure returns (bytes32);

    function verifyCommit(CommitData memory commit, bytes memory signature) external view returns (address);

    function verifyHash(bytes32 hash, bytes memory signature) external pure returns (address);
}
