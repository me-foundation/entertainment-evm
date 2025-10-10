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

    string constant OUTPUT_100K = "./rng_100k.csv";

    // Sample signature data
    bytes sampleSignature1;
    bytes sampleSignature2;
    bytes sampleSignatureIdentical;

    function setUp() public {
        prng = new MockPRNG();

        // Create some sample signatures for testing
        sampleSignature1 = hex"09a0f1a38d41262e87c6bfc526c9a415b94ca4126e6cecba371a0efacf3db47c4ec97521c9ccc9396dcdf8e664ea57d04a1caa956c53180e2330b61908bacff61b";
        sampleSignature2 = hex"1ca0f1a38d41262e87c6bfc526c9a415b94ca4126e6cecba371a0efacf3db47c4ec97521c9ccc9396dcdf8e664ea57d04a1caa956c53180e2330b61908bacff61c";
        // Identical to signature1 for determinism tests
        sampleSignatureIdentical = hex"09a0f1a38d41262e87c6bfc526c9a415b94ca4126e6cecba371a0efacf3db47c4ec97521c9ccc9396dcdf8e664ea57d04a1caa956c53180e2330b61908bacff61b";
    }

    //function testRNGOut() public {
    //    for (uint256 i = 0; i < 1000; i++) {
    //        bytes memory signature = abi.encodePacked(i);
    //        uint32 result = prng.exposed_rng(signature);
    //        console.log(result);
    //    }
    //}

    //function testRNGOutToFile() public {
    //    _generateRNGValues(100000, OUTPUT_100K);
    //}

    function _generateRNGValues(
        uint256 count,
        string memory outputPath
    ) internal {
        for (uint256 i = 0; i < count; i++) {
            bytes memory signature = abi.encodePacked(i);
            uint32 result = prng.exposed_rng(signature);
            string memory row = string(
                abi.encodePacked(vm.toString(uint256(result)))
            );
            vm.writeLine(outputPath, row);
            console.log(result);
        }
    }

    function testRngInRange() public {
        // Test that the output is within the expected range
        uint32 result = prng.exposed_rng(sampleSignature1);

        assertTrue(
            result < prng.BASE_POINTS(),
            "RNG output should be less than BASE_POINTS"
        );
    }

    function testRngDeterminism() public {
        // Test that the same input produces the same output
        uint32 result1 = prng.exposed_rng(sampleSignature1);
        uint32 result2 = prng.exposed_rng(sampleSignatureIdentical);

        assertEq(
            result1,
            result2,
            "Same input signature should produce the same random number"
        );
    }

    function testRngDifferentInputs() public {
        // Test that different inputs produce different outputs
        uint32 result1 = prng.exposed_rng(sampleSignature1);
        uint32 result2 = prng.exposed_rng(sampleSignature2);

        // Note: There's a tiny chance this could fail if both inputs happen to generate the same number
        // But that's extremely unlikely given the space of possible outputs
        assertTrue(
            result1 != result2,
            "Different input signatures should produce different random numbers"
        );
    }

    function testRngZeroLengthSignature() public {
        // Test handling of empty signature
        bytes memory emptySignature = bytes("");

        uint32 result = prng.exposed_rng(emptySignature);

        // Should still produce a value in the correct range
        assertTrue(
            result < prng.BASE_POINTS(),
            "RNG should handle empty signatures and produce output in range"
        );
    }

    function testRngShortSignature() public {
        // Test with a very short signature
        bytes memory shortSignature = bytes("short");

        uint32 result = prng.exposed_rng(shortSignature);

        assertTrue(
            result < prng.BASE_POINTS(),
            "RNG should handle short signatures and produce output in range"
        );
    }
}
