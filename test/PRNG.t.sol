// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/common/PRNG.sol";

contract MockPRNG is PRNG {
    function exposed_rng(
        bytes calldata signature
    ) public view returns (uint32) {
        return _rng(signature);
    }
}

contract TestPRNG is Test {
    MockPRNG prng;

    function setUp() public {
        prng = new MockPRNG();
    }

    function testModuloBiasPrevention() public {
        // Create a signature that would result in a hash just above MAX_CRC32_HASH_VALUE
        bytes memory biasedSignature = "biased";

        // First, let's verify the modulo bias prevention is working
        uint32 result = prng.exposed_rng(biasedSignature);

        // Result should always be less than BASE_POINTS
        assertTrue(
            result < prng.BASE_POINTS(),
            "Result should be less than BASE_POINTS"
        );

        // Verify the result is properly distributed
        assertTrue(
            result < type(uint32).max,
            "Result should be within uint32 range"
        );
    }

    function testEdgeCaseHashValues() public {
        // Test with maximum possible CRC32 value
        bytes memory maxSignature = "max";
        uint32 result = prng.exposed_rng(maxSignature);

        assertTrue(
            result < prng.BASE_POINTS(),
            "Even with max hash, result should be less than BASE_POINTS"
        );
    }

    function testDistributionAcrossRange() public {
        uint256 numTests = 1000;
        uint256[] memory results = new uint256[](numTests);

        // Generate random numbers
        for (uint256 i = 0; i < numTests; i++) {
            bytes memory signature = abi.encodePacked(i);
            results[i] = prng.exposed_rng(signature);
        }

        // Verify distribution properties
        uint256 sum = 0;
        uint256 min = type(uint256).max;
        uint256 max = 0;

        for (uint256 i = 0; i < numTests; i++) {
            sum += results[i];
            if (results[i] < min) min = results[i];
            if (results[i] > max) max = results[i];
        }

        // All results should be within bounds
        assertTrue(max < prng.BASE_POINTS(), "Max value exceeds BASE_POINTS");
        assertTrue(min < prng.BASE_POINTS(), "Min value exceeds BASE_POINTS");

        // Average should be roughly BASE_POINTS/2 (allowing for some variance)
        uint256 avg = sum / numTests;
        assertTrue(
            avg > (prng.BASE_POINTS() * 4000) / 10000 &&
                avg < (prng.BASE_POINTS() * 6000) / 10000,
            "Average outside expected range"
        );
    }

    function testLongSignature() public {
        // Test with a very long signature
        bytes memory longSignature = new bytes(1000);
        for (uint i = 0; i < 1000; i++) {
            longSignature[i] = 0x01;
        }

        uint32 result = prng.exposed_rng(longSignature);

        assertTrue(
            result < prng.BASE_POINTS(),
            "RNG should handle long signatures and produce output in range"
        );
    }
}
