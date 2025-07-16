// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AbstractSignatureVerifier} from "./AbstractSignatureVerifier.sol";

contract LuckyBuySignatureVerifier is AbstractSignatureVerifier {
    struct CommitData {
        uint256 id;
        address receiver;
        address cosigner;
        uint256 seed;
        uint256 counter;
        bytes32 orderHash;
        uint256 amount;
        uint256 reward;
    }

    bytes32 private constant _TYPE_HASH =
        keccak256(
            "CommitData(uint256 id,address receiver,address cosigner,uint256 seed,uint256 counter,bytes32 orderHash,uint256 amount,uint256 reward)"
        );

    constructor() AbstractSignatureVerifier("LuckyBuySignatureVerifier", "1") {}

    function hashOrder(
        address to,
        uint256 value,
        bytes memory data,
        address tokenAddress,
        uint256 tokenId
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(to, value, data, tokenAddress, tokenId));
    }

    function hash(CommitData memory commit) public view returns (bytes32) {
        return
            _hashTyped(
                abi.encode(
                    _TYPE_HASH,
                    commit.id,
                    commit.receiver,
                    commit.cosigner,
                    commit.seed,
                    commit.counter,
                    commit.orderHash,
                    commit.amount,
                    commit.reward
                )
            );
    }

    function verify(
        CommitData memory commit,
        bytes memory signature
    ) public view returns (address) {
        return _verify(hash(commit), signature);
    }
}
