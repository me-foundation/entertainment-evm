// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./common/CRC32.sol";
import {IPRNG} from "./common/interfaces/IPRNG.sol";

/// @title PRNG
/// @notice A contract that provides pseudo-random number generation based on signatures
/// @dev Inherits from CRC32 for hash calculation. Uses a combination of keccak256 and CRC32
/// to generate random numbers within a specified range
contract PRNG is CRC32, IPRNG {
    /// @notice Base points for percentage calculations (100.00%)
    uint256 public constant BASE_POINTS = 10000;

    /// @notice Maximum CRC32 hash value adjusted to prevent modulo bias
    /// @dev Calculated as the largest multiple of BASE_POINTS that fits in uint32
    uint32 public constant MAX_CRC32_HASH_VALUE =
        uint32(type(uint32).max - (type(uint32).max % BASE_POINTS));

    /// @notice Generates a pseudo-random number between 0 and BASE_POINTS
    /// @dev Uses signature as initial entropy, then applies keccak256 and CRC32
    /// repeatedly until a value below MAX_CRC32_HASH_VALUE is found to avoid modulo bias
    /// @param signature The input signature bytes to use as entropy source
    /// @return A pseudo-random number between 0 and BASE_POINTS (0-10000)
    function _rng(bytes calldata signature) internal view returns (uint32) {
        bytes32 hashVal = keccak256(signature);
        uint32 hashNum = crc32(hashVal);

        // Loop until we get a value below MAX_CRC32_HASH_VALUE (to avoid modulo bias)
        while (hashNum >= MAX_CRC32_HASH_VALUE) {
            hashVal = keccak256(abi.encodePacked(hashVal));
            hashNum = crc32(hashVal);
        }

        return uint32(hashNum % BASE_POINTS);
    }

    function rng(bytes calldata signature) public view returns (uint32) {
        return _rng(signature);
    }
}
