// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPRNG
/// @notice Interface for the PRNG contract that provides pseudo-random number generation
interface IPRNG {
    /// @notice Base points for percentage calculations (100.00%)
    function BASE_POINTS() external view returns (uint256);

    /// @notice Maximum CRC32 hash value adjusted to prevent modulo bias
    function MAX_CRC32_HASH_VALUE() external view returns (uint32);

    /// @notice Generates a pseudo-random number between 0 and BASE_POINTS
    /// @param signature The input signature bytes to use as entropy source
    /// @return A pseudo-random number between 0 and BASE_POINTS (0-10000)
    function rng(bytes calldata signature) external view returns (uint32);
}
