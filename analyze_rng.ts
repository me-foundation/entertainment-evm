import * as fs from "fs";

interface RNGData {
  round: number;
  value: number;
}

function analyzeRNG() {
  const csvContent = fs.readFileSync(
    "simulations/rng_all_results.csv",
    "utf-8"
  );
  const lines = csvContent.trim().split("\n");

  const data: RNGData[] = lines.map((line) => {
    const [round, value] = line.split(",").map(Number);
    return { round, value };
  });

  console.log(`Total RNG values analyzed: ${data.length.toLocaleString()}`);

  // Calculate average
  const sum = data.reduce((acc, item) => acc + item.value, 0);
  const average = sum / data.length;
  console.log(`Average RNG value: ${average.toFixed(2)}`);

  // Expected average for 0-9999 range is 4999.5
  console.log(`Expected average: 4999.5`);
  console.log(`Deviation from expected: ${(average - 4999.5).toFixed(2)}`);

  // Count ranges (basis points 0-9999)
  const ranges = [
    { name: "0-999", min: 0, max: 999, count: 0 },
    { name: "1000-1999", min: 1000, max: 1999, count: 0 },
    { name: "2000-2999", min: 2000, max: 2999, count: 0 },
    { name: "3000-3999", min: 3000, max: 3999, count: 0 },
    { name: "4000-4999", min: 4000, max: 4999, count: 0 },
    { name: "5000-5999", min: 5000, max: 5999, count: 0 },
    { name: "6000-6999", min: 6000, max: 6999, count: 0 },
    { name: "7000-7999", min: 7000, max: 7999, count: 0 },
    { name: "8000-8999", min: 8000, max: 8999, count: 0 },
    { name: "9000-9999", min: 9000, max: 9999, count: 0 },
  ];

  // Count values in each range
  data.forEach((item) => {
    for (const range of ranges) {
      if (item.value >= range.min && item.value <= range.max) {
        range.count++;
        break;
      }
    }
  });

  console.log("\nDistribution by range:");
  ranges.forEach((range) => {
    const percentage = ((range.count / data.length) * 100).toFixed(2);
    console.log(
      `${range.name}: ${range.count.toLocaleString()} (${percentage}%)`
    );
  });

  // Expected is 10% for each range
  console.log("\nExpected: 10% per range");

  // Find min/max values
  let min = data[0].value;
  let max = data[0].value;
  data.forEach((item) => {
    if (item.value < min) min = item.value;
    if (item.value > max) max = item.value;
  });

  console.log(`\nMin value: ${min}`);
  console.log(`Max value: ${max}`);
  console.log(
    `Range coverage: ${min === 0 && max === 9999 ? "Full (0-9999)" : "Partial"}`
  );

  // Statistical tests for uniformity
  console.log("\n=== UNIFORMITY TESTS ===");

  // Chi-square test
  const expected = data.length / 10; // Expected count per range
  let chiSquare = 0;
  ranges.forEach((range) => {
    const observed = range.count;
    chiSquare += Math.pow(observed - expected, 2) / expected;
  });

  console.log(`Chi-square statistic: ${chiSquare.toFixed(4)}`);
  console.log(`Degrees of freedom: 9`);

  // Critical values for chi-square (df=9) at different confidence levels
  const criticalValues = {
    "90%": 14.684,
    "95%": 16.919,
    "99%": 21.666,
    "99.9%": 27.877,
    "99.99%": 32.909,
  };

  console.log(`\nChi-square test results:`);
  Object.entries(criticalValues).forEach(([confidence, critical]) => {
    const passes = chiSquare < critical;
    console.log(
      `${confidence} confidence (critical: ${critical}): ${
        passes ? "PASS" : "FAIL"
      }`
    );
  });

  // Calculate standard deviation of range counts
  const rangeCounts = ranges.map((r) => r.count);
  const meanCount = rangeCounts.reduce((a, b) => a + b, 0) / rangeCounts.length;
  const variance =
    rangeCounts.reduce(
      (acc, count) => acc + Math.pow(count - meanCount, 2),
      0
    ) / rangeCounts.length;
  const stdDev = Math.sqrt(variance);

  console.log(`\nRange count statistics:`);
  console.log(`Mean count per range: ${meanCount.toFixed(2)}`);
  console.log(`Standard deviation: ${stdDev.toFixed(2)}`);
  console.log(
    `Coefficient of variation: ${((stdDev / meanCount) * 100).toFixed(4)}%`
  );

  // Find largest deviation from expected
  let maxDeviation = 0;
  let maxDeviationRange = "";
  ranges.forEach((range) => {
    const deviation = Math.abs(range.count - expected);
    if (deviation > maxDeviation) {
      maxDeviation = deviation;
      maxDeviationRange = range.name;
    }
  });

  console.log(
    `\nLargest deviation: ${maxDeviation.toFixed(
      0
    )} in range ${maxDeviationRange}`
  );
  console.log(
    `Deviation as % of expected: ${((maxDeviation / expected) * 100).toFixed(
      4
    )}%`
  );

  // Overall assessment with explanation
  console.log("\n=== ASSESSMENT ===");

  const passes99_99 = chiSquare < criticalValues["99.99%"];
  const passes99_9 = chiSquare < criticalValues["99.9%"];
  const passes99 = chiSquare < criticalValues["99%"];
  const passes95 = chiSquare < criticalValues["95%"];

  if (passes99_99) {
    console.log("🏆 EXCELLENT: RNG passes 99.99% confidence test");
    console.log("   Extremely high certainty of uniform distribution");
  } else if (passes99_9) {
    console.log("✅ VERY GOOD: RNG passes 99.9% confidence test");
    console.log("   Very high certainty of uniform distribution");
  } else if (passes99) {
    console.log("✅ GOOD: RNG passes 99% confidence test");
    console.log("   High certainty of uniform distribution");
  } else if (passes95) {
    console.log("⚠️  ACCEPTABLE: RNG passes 95% confidence test");
    console.log("   Reasonable certainty of uniform distribution");
  } else {
    console.log("❌ POOR: RNG fails 95% confidence test");
    console.log("   Strong evidence of non-uniform distribution");
  }

  console.log("\n=== ACCURACY EXPLANATION ===");
  console.log("Chi-square test accuracy depends on sample size:");
  console.log(
    `• Sample size: ${data.length.toLocaleString()} (EXCELLENT - very reliable)`
  );
  console.log("• 95% confidence: 5% chance of false positive");
  console.log("• 99% confidence: 1% chance of false positive");
  console.log("• 99.9% confidence: 0.1% chance of false positive");
  console.log("• 99.99% confidence: 0.01% chance of false positive");
  console.log(
    "\nWith 10M+ samples, results are highly reliable for detecting bias."
  );

  // Additional context
  const expectedStdDev = Math.sqrt(expected * (1 - 0.1)); // For binomial
  console.log(`\nExpected standard deviation: ~${expectedStdDev.toFixed(2)}`);
  console.log(`Observed standard deviation: ${stdDev.toFixed(2)}`);
  console.log(`Ratio: ${(stdDev / expectedStdDev).toFixed(3)}x expected`);
}

analyzeRNG();
