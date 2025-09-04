// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/PRNG.sol";

contract RNGTest is Test {
    PRNG prng;
    string constant OUTPUT_FILE = "./rng_results.csv";

    function setUp() public {
        prng = new PRNG();
    }

    function getRNGIterations() internal view returns (uint256) {
        try vm.envUint("RNG_ITERATIONS") returns (uint256 envIterations) {
            return envIterations;
        } catch {
            return 1_000_000;
        }
    }

    function getRNGOutputFile() internal view returns (string memory) {
        try vm.envString("RNG_OUTPUT_FILE") returns (string memory envFile) {
            return envFile;
        } catch {
            uint256 seed = getRNGSeed();
            return
                string(
                    abi.encodePacked(
                        "simulations/rng_results_",
                        vm.toString(seed),
                        ".csv"
                    )
                );
        }
    }

    function getRNGSeed() internal view returns (uint256) {
        try vm.envUint("RNG_SEED") returns (uint256 envSeed) {
            return envSeed;
        } catch {
            return 12345;
        }
    }

    function testRNGOutput() public {
        uint256 iterations = getRNGIterations();
        string memory outputFile = getRNGOutputFile();
        uint256 baseSeed = getRNGSeed();

        console.log("Testing RNG Output");
        console.log("Iterations:", iterations);
        console.log("Output file:", outputFile);
        console.log("Base seed:", baseSeed);

        for (uint256 i = 0; i < iterations; i++) {
            // Create a signature-like input for the RNG
            // Using incrementing seed + round number to simulate different signatures
            bytes memory mockSignature = abi.encodePacked(
                keccak256(abi.encode(baseSeed + i)), // r component
                keccak256(abi.encode(baseSeed + i + 1)), // s component
                uint8(27 + (i % 2)) // v component
            );

            uint256 rngValue = prng.rng(mockSignature);

            // Write to CSV
            string memory row = string(
                abi.encodePacked(vm.toString(i + 1), ",", vm.toString(rngValue))
            );
            vm.writeLine(outputFile, row);
        }

        console.log("RNG testing completed. Results written to:", outputFile);
    }

    function testRNGDistribution() public {
        uint256 iterations = getRNGIterations();
        string memory outputFile = "rng_distribution.csv";
        uint256 baseSeed = getRNGSeed();

        console.log("Testing RNG Distribution");
        console.log("Iterations:", iterations);

        // Buckets for distribution analysis (0-999, 1000-1999, ..., 9000-9999)
        uint256[10] memory buckets;

        // Write CSV header
        vm.writeLine(outputFile, "round,rng_value,bucket");

        for (uint256 i = 0; i < iterations; i++) {
            bytes memory mockSignature = abi.encodePacked(
                keccak256(abi.encode(baseSeed + i)),
                keccak256(abi.encode(baseSeed + i + 1)),
                uint8(27 + (i % 2))
            );

            uint256 rngValue = prng.rng(mockSignature);
            uint256 bucket = rngValue / 1000; // 0-9 buckets
            if (bucket > 9) bucket = 9; // Cap at bucket 9

            buckets[bucket]++;

            // Write to CSV
            string memory row = string(
                abi.encodePacked(
                    vm.toString(i + 1),
                    ",",
                    vm.toString(rngValue),
                    ",",
                    vm.toString(bucket)
                )
            );
            vm.writeLine(outputFile, row);
        }

        // Log distribution results
        console.log("Distribution Results:");
        for (uint256 i = 0; i < 10; i++) {
            console.log("Bucket", i, ":", buckets[i]);
        }

        console.log(
            "Distribution testing completed. Results written to:",
            outputFile
        );
    }
}
