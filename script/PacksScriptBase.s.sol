// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/PacksInitializable.sol";
import "../src/PRNG.sol";
import "../src/common/SignatureVerifier/PacksSignatureVerifierUpgradeable.sol";

contract PacksScriptBase is Script {
    // Common signing utilities
    function signPack(
        PacksInitializable packs,
        uint256 packPrice,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets,
        uint256 signerKey
    ) internal pure returns (bytes memory) {
        bytes32 packHash = packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets);
        return _signMessage(packHash, signerKey);
    }

    function signCommit(
        PacksInitializable packs,
        uint256 commitId,
        address receiver,
        address cosigner,
        uint256 seed,
        uint256 counter,
        uint256 packPrice,
        PacksSignatureVerifierUpgradeable.BucketData[] memory buckets,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        PacksSignatureVerifierUpgradeable.CommitData memory commitData = PacksSignatureVerifierUpgradeable.CommitData({
            id: commitId,
            receiver: receiver,
            cosigner: cosigner,
            seed: seed,
            counter: counter,
            packPrice: packPrice,
            buckets: buckets,
            packHash: packs.hashPack(PacksSignatureVerifierUpgradeable.PackType.NFT, packPrice, buckets)
        });

        bytes32 digest = packs.hashCommit(commitData);
        return _signMessage(digest, signerKey);
    }

    function signOrder(
        PacksInitializable packs,
        PacksSignatureVerifierUpgradeable.CommitData memory commitData,
        address marketplace,
        uint256 orderAmount,
        bytes memory orderData,
        address token,
        uint256 tokenId,
        uint256 payoutAmount,
        PacksSignatureVerifierUpgradeable.FulfillmentOption choice,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        bytes32 digest = packs.hashCommit(commitData);
        bytes32 fulfillmentHash =
            packs.hashFulfillment(digest, marketplace, orderAmount, orderData, token, tokenId, payoutAmount, choice);
        return _signMessage(fulfillmentHash, signerKey);
    }

    // Local implementation of hashChoice for script purposes
    function hashChoice(bytes32 digest, PacksSignatureVerifierUpgradeable.FulfillmentOption choice)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(digest, choice));
    }

    function signChoice(
        PacksInitializable packs,
        PacksSignatureVerifierUpgradeable.CommitData memory commitData,
        PacksSignatureVerifierUpgradeable.FulfillmentOption choice,
        uint256 signerKey
    ) internal view returns (bytes memory) {
        bytes32 digest = packs.hashCommit(commitData);
        bytes32 choiceHash = hashChoice(digest, choice);
        return _signMessage(choiceHash, signerKey);
    }

    function _signMessage(bytes32 hash, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function setupDefaultBuckets() internal pure returns (PacksSignatureVerifierUpgradeable.BucketData[] memory buckets) {
        buckets = new PacksSignatureVerifierUpgradeable.BucketData[](3);

        // Bucket 1: 80% chance
        buckets[0] = PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 8000, minValue: 0.01 ether, maxValue: 0.02 ether});

        // Bucket 2: 10% chance
        buckets[1] = PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 1000, minValue: 0.03 ether, maxValue: 0.04 ether});

        // Bucket 3: 10% chance
        buckets[2] = PacksSignatureVerifierUpgradeable.BucketData({oddsBps: 1000, minValue: 0.05 ether, maxValue: 0.06 ether});
    }
}
