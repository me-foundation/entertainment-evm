// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./AbstractSignatureVerifierUpgradeable.sol";

contract LuckyBuySignatureVerifierUpgradeable is
    AbstractSignatureVerifierUpgradeable
{
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

    function __LuckyBuySignatureVerifier_init(
        string memory name,
        string memory version
    ) internal onlyInitializing {
        __AbstractSignatureVerifier_init(name, version);
    }

    /// @notice Hashes a commit
    /// @param commit Commit to hash
    /// @return Hash of the commit
    function hash(CommitData memory commit) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
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
                )
            );
    }

    /// @notice Utility function. Hashes an order to calculate an orderHash for CommitData
    /// @param to The address of the receiver
    /// @param value The value of the order
    /// @param data The data of the order
    /// @param tokenAddress The address of the token
    /// @param tokenId The id of the token
    /// @return Hash of the order
    function hashOrder(
        address to,
        uint256 value,
        bytes memory data,
        address tokenAddress,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(to, value, data, tokenAddress, tokenId));
    }

    /// @notice Verifies a commit against a signature. Convenience function for unit tests/off chain checks without an EIP712 implementation. LuckyBuy calls the internal _verify function because we log the digest.
    /// @param commit The commit to verify
    /// @param signature The signature of the commit
    /// @return The address of the cosigner
    function verify(
        CommitData memory commit,
        bytes memory signature
    ) public view returns (address) {
        return super.verify(hash(commit), signature);
    }
}
