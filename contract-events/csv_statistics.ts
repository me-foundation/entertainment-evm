import { parse } from "csv-parse/sync";
import * as fs from "fs";

interface FulfillmentEvent {
  "Block Number": string;
  "Transaction Hash": string;
  "Event Name": string;
  sender: string;
  commitId: string;
  rng: string;
  odds: string;
  win: string;
  token: string;
  tokenId: string;
  amount: string;
  receiver: string;
  fee: string;
  digest: string;
}

function analyzeFulfillmentData(csvPath: string) {
  // Read and parse CSV
  const fileContent = fs.readFileSync(csvPath, "utf-8");
  const records = parse(fileContent, {
    columns: true,
    skip_empty_lines: true,
  }) as FulfillmentEvent[];

  // Convert string values to appropriate types
  const events = records.map((record) => ({
    ...record,
    rng: parseInt(record.rng),
    odds: parseInt(record.odds),
    win: record.win.toLowerCase() === "true",
  }));

  // Basic statistics
  const oddsStats = calculateStats(events.map((e) => e.odds));
  const rngStats = calculateStats(events.map((e) => e.rng));
  const totalEvents = events.length;
  const wins = events.filter((e) => e.win).length;
  const winRate = (wins / totalEvents) * 100;

  // PRNG Analysis
  const prngAnalysis = analyzePRNGPerformance(events);

  // Percentage-level analysis (0-99%)
  const percentageAnalysis = new Array(100).fill(null).map((_, percentage) => {
    const eventsInRange = events.filter(
      (e) => Math.floor((e.odds / 10000) * 100) === percentage
    );
    const winCount = eventsInRange.filter((e) => e.win).length;
    const totalInRange = eventsInRange.length;

    return {
      percentage,
      count: totalInRange,
      winCount,
      winRate: totalInRange > 0 ? (winCount / totalInRange) * 100 : 0,
      expectedWinRate: percentage,
      deviation:
        totalInRange > 0 ? (winCount / totalInRange) * 100 - percentage : 0,
    };
  });

  // Filter out percentages with no data
  const validPercentages = percentageAnalysis.filter((p) => p.count > 0);

  // Calculate average deviation from expected win rate
  const avgDeviation =
    validPercentages.reduce((sum, p) => sum + Math.abs(p.deviation), 0) /
    validPercentages.length;

  // Find significant deviations (more than 10% from expected)
  const significantDeviations = validPercentages.filter(
    (p) => Math.abs(p.deviation) > 10
  );

  // RNG vs Odds Analysis at percentage level
  const rngVsOddsByPercentage = validPercentages.map((p) => {
    const eventsInRange = events.filter(
      (e) => Math.floor((e.odds / 10000) * 100) === p.percentage
    );
    const rngValues = eventsInRange.map((e) => e.rng);
    const oddsValues = eventsInRange.map((e) => e.odds);

    return {
      percentage: p.percentage,
      correlation: calculateCorrelation(rngValues, oddsValues),
      count: eventsInRange.length,
    };
  });

  // Find percentages with significant RNG-Odds correlation
  const significantCorrelations = rngVsOddsByPercentage.filter(
    (p) => Math.abs(p.correlation) > 0.3
  );

  // Export results to JSON
  const results = {
    basicStats: {
      odds: oddsStats,
      rng: rngStats,
      overallWinRate: winRate,
    },
    prngAnalysis: {
      distributionUniformity: prngAnalysis.distributionUniformity,
      chiSquareStatistic: prngAnalysis.chiSquareStatistic,
      sequentialCorrelation: prngAnalysis.sequentialCorrelation,
      percentagePointAnalysis: prngAnalysis.percentagePointAnalysis,
      qualityIndicators: prngAnalysis.qualityIndicators,
      interpretation: prngAnalysis.interpretation,
    },
    percentageAnalysis: {
      averageDeviation: avgDeviation,
      significantDeviations,
      detailedAnalysis: validPercentages,
      rngVsOddsAnalysis: rngVsOddsByPercentage,
    },
  };

  fs.writeFileSync(
    "fulfillment_analysis.json",
    JSON.stringify(results, null, 2)
  );

  // Human-readable output
  console.log("\n=== Fulfillment Events Analysis Summary ===");

  console.log("\n1. Basic Statistics");
  console.log("------------------");
  console.log(`Total Events: ${totalEvents}`);
  console.log(`Overall Win Rate: ${winRate.toFixed(2)}%`);
  console.log("\nOdds Statistics (out of 10,000):");
  console.log(oddsStats);
  console.log("\nRNG Statistics (out of 10,000):");
  console.log(rngStats);

  console.log("\n2. PRNG Performance Analysis");
  console.log("---------------------------");
  console.log("\nDistribution Uniformity (10% Ranges):");
  prngAnalysis.distributionUniformity.forEach((d) => {
    console.log(
      `${d.range}: ${d.count} values (Expected: ${d.expected.toFixed(
        2
      )}, Deviation: ${d.deviation}, ${d.stdDevsFromMean} std devs from mean)`
    );
  });

  console.log("\nChi-Square Analysis:");
  console.log(
    `Chi-Square Statistic (10% ranges): ${prngAnalysis.chiSquareStatistic.toFixed(
      2
    )} - ${prngAnalysis.interpretation.chiSquare.status}`
  );
  console.log(
    `Chi-Square Statistic (per point): ${prngAnalysis.percentagePointAnalysis.chiSquareStatistic.toFixed(
      2
    )} - ${prngAnalysis.interpretation.chiSquarePerPoint.status}`
  );
  console.log(
    `Sequential Correlation: ${prngAnalysis.sequentialCorrelation.toFixed(
      4
    )} - ${prngAnalysis.interpretation.sequentialCorrelation.status}`
  );

  console.log("\nKolmogorov-Smirnov Test:");
  console.log(`D-statistic: ${prngAnalysis.ksTest.statistic.toFixed(4)}`);
  console.log(`P-value: ${prngAnalysis.ksTest.pValue.toFixed(4)}`);
  console.log(`Interpretation: ${prngAnalysis.interpretation.ksTest.message}`);

  console.log("\nGap Test Analysis:");
  prngAnalysis.gapTest.results.forEach((result) => {
    if (result.meanGap > 0) {
      // Only show ranges with data
      console.log(`\nRange ${result.range}:`);
      console.log(`  Mean Gap: ${result.meanGap.toFixed(2)}`);
      console.log(`  Expected Gap: ${result.expectedGap.toFixed(2)}`);
      console.log(`  Chi-Square: ${result.chiSquare.toFixed(2)}`);
      console.log(`  P-value: ${result.pValue.toFixed(4)}`);
      console.log(`  Status: ${result.status}`);
    }
  });
  console.log(
    `\nOverall Gap Test Status: ${prngAnalysis.gapTest.overallStatus}`
  );

  console.log("\nPoker Test Analysis:");
  prngAnalysis.pokerTest.results.forEach((result) => {
    console.log(`\n${result.pattern}:`);
    console.log(`  Observed: ${result.observed}`);
    console.log(`  Expected: ${result.expected.toFixed(2)}`);
    console.log(`  Deviation: ${result.deviation.toFixed(2)}%`);
    console.log(`  Status: ${result.status}`);
  });
  console.log(
    `\nOverall Poker Test Status: ${prngAnalysis.pokerTest.overallStatus}`
  );

  console.log("\n3. Win Rate Analysis");
  console.log("-------------------");
  console.log(
    `Average Deviation from Expected Win Rate: ${avgDeviation.toFixed(2)}%`
  );
  console.log(`Number of Percentages with Data: ${validPercentages.length}`);

  if (significantDeviations.length > 0) {
    console.log("\nSignificant Deviations from Expected Win Rate:");
    significantDeviations.forEach((p) => {
      console.log(
        `${p.percentage}%: ${p.winRate.toFixed(2)}% win rate (Expected: ${
          p.expectedWinRate
        }%, Deviation: ${p.deviation.toFixed(2)}%)`
      );
    });
  }

  console.log("\n4. RNG vs Odds Correlation");
  console.log("-------------------------");
  if (significantCorrelations.length > 0) {
    console.log("\nPercentages with Significant RNG-Odds Correlation:");
    significantCorrelations.forEach((p) => {
      console.log(
        `${p.percentage}%: Correlation = ${p.correlation.toFixed(4)} (${
          p.count
        } events)`
      );
    });
  }

  console.log("\n5. Statistical Interpretation");
  console.log("---------------------------");
  console.log("\nKey Findings:");
  console.log(
    `1. Distribution Uniformity: ${prngAnalysis.interpretation.chiSquare.message}`
  );
  console.log(
    `2. Percentage Point Distribution: ${prngAnalysis.interpretation.chiSquarePerPoint.message}`
  );
  console.log(
    `3. Sequential Correlation: ${prngAnalysis.interpretation.sequentialCorrelation.message}`
  );
  console.log(
    `4. Significant Deviations: ${prngAnalysis.interpretation.significantDeviations.message}`
  );
  console.log(`5. K-S Test: ${prngAnalysis.interpretation.ksTest.message}`);
  console.log(`6. Gap Test: ${prngAnalysis.interpretation.gapTest.message}`);
  console.log(
    `7. Poker Test: ${prngAnalysis.interpretation.pokerTest.message}`
  );

  console.log(
    "\nAnalysis results have been saved to fulfillment_analysis.json"
  );
}

function calculateStats(numbers: number[]) {
  const sorted = [...numbers].sort((a, b) => a - b);
  const sum = numbers.reduce((a, b) => a + b, 0);
  const mean = sum / numbers.length;
  const variance =
    numbers.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / numbers.length;
  const stdDev = Math.sqrt(variance);

  return {
    count: numbers.length,
    mean: mean.toFixed(2),
    median: sorted[Math.floor(sorted.length / 2)],
    stdDev: stdDev.toFixed(2),
    min: sorted[0],
    max: sorted[sorted.length - 1],
    q1: sorted[Math.floor(sorted.length * 0.25)],
    q3: sorted[Math.floor(sorted.length * 0.75)],
  };
}

function calculateCorrelation(x: number[], y: number[]) {
  const n = x.length;
  const sumX = x.reduce((a, b) => a + b, 0);
  const sumY = y.reduce((a, b) => a + b, 0);
  const sumXY = x.reduce((a, b, i) => a + b * y[i], 0);
  const sumX2 = x.reduce((a, b) => a + b * b, 0);
  const sumY2 = y.reduce((a, b) => a + b * b, 0);

  const numerator = n * sumXY - sumX * sumY;
  const denominator = Math.sqrt(
    (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY)
  );

  return denominator === 0 ? 0 : numerator / denominator;
}

function analyzePRNGPerformance(events: Array<{ rng: number }>) {
  const rngValues = events.map((e) => e.rng);
  const totalValues = rngValues.length;

  // Calculate standard deviation for the entire dataset
  const mean = rngValues.reduce((a, b) => a + b, 0) / totalValues;
  const stdDev = Math.sqrt(
    rngValues.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / totalValues
  );

  // K-S Test for Uniformity
  const ksTest = performKSTest(rngValues);

  // Gap Test Analysis
  const gapTest = performGapTest(rngValues);

  // Poker Test Analysis
  const pokerTest = performPokerTest(rngValues);

  // 1. Distribution Analysis - Percentage Points
  const percentageDistribution = new Array(100).fill(0);
  rngValues.forEach((value) => {
    // Convert to percentage (0-100)
    const percentage = Math.floor((value / 10000) * 100);
    percentageDistribution[percentage]++;
  });

  const expectedPerPoint = totalValues / 100;

  // Calculate chi-square for percentage points
  const chiSquarePerPoint = percentageDistribution.reduce((sum, observed) => {
    return sum + Math.pow(observed - expectedPerPoint, 2) / expectedPerPoint;
  }, 0);

  // Find significant deviations with standard deviation context
  const significantDeviations = percentageDistribution
    .map((count, percentage) => {
      const deviation = ((count - expectedPerPoint) / expectedPerPoint) * 100;
      const stdDevsFromMean =
        (count - expectedPerPoint) / Math.sqrt(expectedPerPoint);
      return {
        percentage,
        count,
        expected: expectedPerPoint,
        deviation,
        stdDevsFromMean,
        isSignificant: Math.abs(stdDevsFromMean) > 2, // More than 2 standard deviations
      };
    })
    .filter((d) => d.isSignificant);

  // 2. Original range-based analysis
  const rangeSize = 1000; // Divide 0-10000 into 10 equal ranges
  const distribution = new Array(10).fill(0);

  rngValues.forEach((value) => {
    const index = Math.min(Math.floor(value / rangeSize), 9);
    distribution[index]++;
  });

  const expectedCount = totalValues / 10;
  const chiSquare = distribution.reduce((sum, observed) => {
    return sum + Math.pow(observed - expectedCount, 2) / expectedCount;
  }, 0);

  // 3. Sequential Analysis
  const sequentialPairs = [];
  for (let i = 0; i < rngValues.length - 1; i++) {
    sequentialPairs.push({
      current: rngValues[i],
      next: rngValues[i + 1],
    });
  }

  const sequentialCorrelation = calculateCorrelation(
    sequentialPairs.map((p) => p.current),
    sequentialPairs.map((p) => p.next)
  );

  // 4. Evaluate PRNG quality with statistical context
  const distributionUniformity = distribution.map((count, index) => {
    const deviation = ((count - expectedCount) / expectedCount) * 100;
    const stdDevsFromMean = (count - expectedCount) / Math.sqrt(expectedCount);
    return {
      range: `${index * 10}-${(index + 1) * 10}%`,
      count,
      expected: expectedCount,
      deviation: deviation.toFixed(2) + "%",
      stdDevsFromMean: stdDevsFromMean.toFixed(2),
      status: Math.abs(stdDevsFromMean) > 2 ? "WARNING" : "PASS",
    };
  });

  // Add K-S test results to interpretation
  const interpretation = {
    chiSquare: {
      value: chiSquare,
      threshold: 16.92,
      status: chiSquare < 16.92 ? "PASS" : "WARNING",
      message:
        chiSquare < 16.92
          ? "Distribution appears uniform (within 95% confidence interval)"
          : "Distribution deviates significantly from uniform (outside 95% confidence interval)",
    },
    chiSquarePerPoint: {
      value: chiSquarePerPoint,
      threshold: 123.225,
      status: chiSquarePerPoint < 123.225 ? "PASS" : "WARNING",
      message:
        chiSquarePerPoint < 123.225
          ? "Percentage point distribution appears uniform (within 95% confidence interval)"
          : "Percentage point distribution deviates significantly (outside 95% confidence interval)",
    },
    sequentialCorrelation: {
      value: sequentialCorrelation,
      threshold: 0.1,
      status: Math.abs(sequentialCorrelation) < 0.1 ? "PASS" : "WARNING",
      message:
        Math.abs(sequentialCorrelation) < 0.1
          ? "Low correlation between sequential numbers (within acceptable range)"
          : `High correlation between sequential numbers (${Math.abs(
              sequentialCorrelation
            ).toFixed(2)} standard deviations from expected)`,
    },
    significantDeviations: {
      count: significantDeviations.length,
      threshold: 5,
      status: significantDeviations.length <= 5 ? "PASS" : "WARNING",
      message:
        significantDeviations.length <= 5
          ? "Acceptable number of significant deviations (within 2 standard deviations)"
          : `Too many significant deviations (${significantDeviations.length} points outside 2 standard deviations)`,
    },
    ksTest: {
      value: ksTest.statistic,
      pValue: ksTest.pValue,
      status: ksTest.pValue > 0.05 ? "PASS" : "WARNING",
      message:
        ksTest.pValue > 0.05
          ? "K-S test indicates uniform distribution (p > 0.05)"
          : "K-S test indicates non-uniform distribution (p <= 0.05)",
    },
    gapTest: {
      results: gapTest.results,
      status: gapTest.overallStatus,
      message:
        gapTest.overallStatus === "PASS"
          ? "Gap test indicates no significant clustering or cycles"
          : "Gap test indicates potential clustering or cyclic patterns",
    },
    pokerTest: {
      results: pokerTest.results,
      status: pokerTest.overallStatus,
      message:
        pokerTest.overallStatus === "PASS"
          ? "Poker test indicates random digit distribution"
          : "Poker test indicates potential digit patterns",
    },
  };

  // PRNG Quality Assessment
  const assessment = {
    distributionUniformity,
    chiSquareStatistic: chiSquare,
    sequentialCorrelation,
    ksTest,
    gapTest,
    pokerTest,
    percentagePointAnalysis: {
      chiSquareStatistic: chiSquarePerPoint,
      significantDeviations,
      distribution: percentageDistribution.map((count, percentage) => {
        const stdDevsFromMean =
          (count - expectedPerPoint) / Math.sqrt(expectedPerPoint);
        return {
          percentage,
          count,
          expected: expectedPerPoint,
          deviation:
            (((count - expectedPerPoint) / expectedPerPoint) * 100).toFixed(2) +
            "%",
          stdDevsFromMean: stdDevsFromMean.toFixed(2),
          status: Math.abs(stdDevsFromMean) > 2 ? "WARNING" : "PASS",
        };
      }),
    },
    qualityIndicators: {
      isUniformlyDistributed: chiSquare < 16.92 && ksTest.pValue > 0.05,
      hasLowSequentialCorrelation: Math.abs(sequentialCorrelation) < 0.1,
      hasSignificantPercentageDeviations: significantDeviations.length > 0,
      hasNoSignificantGaps: gapTest.overallStatus === "PASS",
      hasRandomDigits: pokerTest.overallStatus === "PASS",
      distributionBias: distributionUniformity.map((d) => ({
        range: d.range,
        bias: d.deviation,
        stdDevsFromMean: d.stdDevsFromMean,
        status:
          Math.abs(parseFloat(d.stdDevsFromMean)) > 2 ? "WARNING" : "PASS",
      })),
    },
    interpretation,
  };

  return assessment;
}

// Add K-S test implementation
function performKSTest(data: number[]): { statistic: number; pValue: number } {
  const n = data.length;
  const sortedData = [...data].sort((a, b) => a - b);

  // Normalize data to [0,1] range
  const normalizedData = sortedData.map((x) => x / 10000);

  // Calculate empirical CDF
  const empiricalCDF = normalizedData.map((x, i) => (i + 1) / n);

  // Calculate theoretical CDF (uniform distribution)
  const theoreticalCDF = normalizedData.map((x) => x);

  // Calculate D statistic (maximum difference between empirical and theoretical CDFs)
  const differences = empiricalCDF.map((ecdf, i) =>
    Math.max(
      Math.abs(ecdf - theoreticalCDF[i]),
      Math.abs((i > 0 ? empiricalCDF[i - 1] : 0) - theoreticalCDF[i])
    )
  );
  const dStatistic = Math.max(...differences);

  // Calculate p-value using the asymptotic approximation
  // For large n, sqrt(n) * D follows the Kolmogorov distribution
  const sqrtN = Math.sqrt(n);
  const lambda = sqrtN * dStatistic;

  // Calculate p-value using the asymptotic formula
  let pValue = 0;
  const terms = 100; // Number of terms to use in the series
  for (let k = 1; k <= terms; k++) {
    pValue += Math.pow(-1, k - 1) * Math.exp(-2 * k * k * lambda * lambda);
  }
  pValue = 2 * pValue;

  return {
    statistic: dStatistic,
    pValue: Math.min(1, Math.max(0, pValue)), // Ensure p-value is between 0 and 1
  };
}

// Add Gap Test implementation
function performGapTest(data: number[]): {
  results: Array<{
    range: string;
    meanGap: number;
    expectedGap: number;
    chiSquare: number;
    pValue: number;
    status: "PASS" | "WARNING";
  }>;
  overallStatus: "PASS" | "WARNING";
} {
  // Define test ranges (10 equal ranges from 0-10000)
  const ranges = Array.from({ length: 10 }, (_, i) => ({
    min: i * 1000,
    max: (i + 1) * 1000 - 1,
    label: `${i * 10}-${(i + 1) * 10}%`,
  }));

  const results = ranges.map((range) => {
    // Find all indices where values fall in this range
    const hits = data
      .map((value, index) => ({ value, index }))
      .filter(({ value }) => value >= range.min && value <= range.max)
      .map(({ index }) => index);

    if (hits.length < 2) {
      return {
        range: range.label,
        meanGap: 0,
        expectedGap: 0,
        chiSquare: 0,
        pValue: 1,
        status: "PASS" as const,
      };
    }

    // Calculate gaps between hits
    const gaps = [];
    for (let i = 1; i < hits.length; i++) {
      gaps.push(hits[i] - hits[i - 1] - 1); // -1 because we want the number of values between hits
    }

    const meanGap = gaps.reduce((a, b) => a + b, 0) / gaps.length;

    // Expected gap follows geometric distribution
    // For uniform distribution, p = range_size/total_range
    const p = (range.max - range.min + 1) / 10000;
    const expectedGap = (1 - p) / p;

    // Chi-square test for geometric distribution
    // Group gaps into bins to ensure sufficient counts
    const maxGap = Math.max(...gaps);
    const numBins = Math.min(10, Math.ceil(Math.sqrt(gaps.length))); // Use sqrt(n) bins or max 10
    const binSize = Math.ceil(maxGap / numBins);

    const observedFreq = new Array(numBins).fill(0);
    gaps.forEach((gap) => {
      const binIndex = Math.min(Math.floor(gap / binSize), numBins - 1);
      observedFreq[binIndex]++;
    });

    // Calculate expected frequencies for each bin
    const expectedFreq = observedFreq.map((_, binIndex) => {
      const binStart = binIndex * binSize;
      const binEnd = (binIndex + 1) * binSize - 1;
      let expected = 0;
      for (let gap = binStart; gap <= binEnd; gap++) {
        expected += gaps.length * p * Math.pow(1 - p, gap);
      }
      return expected;
    });

    // Calculate chi-square statistic
    const chiSquare = observedFreq.reduce((sum, obs, i) => {
      const exp = expectedFreq[i];
      // Skip bins with expected frequency < 5
      if (exp < 5) return sum;
      return sum + Math.pow(obs - exp, 2) / exp;
    }, 0);

    // Calculate degrees of freedom (number of bins with expected frequency >= 5)
    const degreesOfFreedom = expectedFreq.filter((exp) => exp >= 5).length - 1;

    // Calculate p-value using chi-square distribution
    // For large degrees of freedom, we can use the normal approximation
    const pValue =
      1 -
      normalCDF(Math.sqrt(2 * chiSquare) - Math.sqrt(2 * degreesOfFreedom - 1));

    const status: "PASS" | "WARNING" = pValue > 0.05 ? "PASS" : "WARNING";

    return {
      range: range.label,
      meanGap,
      expectedGap,
      chiSquare,
      pValue,
      status,
    };
  });

  // Overall status based on number of ranges that fail
  const overallStatus: "PASS" | "WARNING" =
    results.filter((r) => r.status === "WARNING").length > 2
      ? "WARNING"
      : "PASS";

  return { results, overallStatus };
}

// Add Poker Test implementation
function performPokerTest(data: number[]): {
  results: Array<{
    pattern: string;
    observed: number;
    expected: number;
    deviation: number;
    status: "PASS" | "WARNING";
  }>;
  overallStatus: "PASS" | "WARNING";
} {
  // Define patterns and their expected probabilities
  const patterns = [
    { name: "Four of a Kind", probability: 0.0001 }, // 4 same digits
    { name: "Three of a Kind", probability: 0.004 }, // 3 same digits
    { name: "Two Pairs", probability: 0.027 }, // 2 pairs of same digits
    { name: "One Pair", probability: 0.432 }, // 1 pair of same digits
    { name: "No Pattern", probability: 0.5369 }, // All digits different
  ];

  // Count occurrences of each pattern
  const counts = new Array(patterns.length).fill(0);

  data.forEach((value) => {
    // Convert to 4-digit string with leading zeros
    const digits = value.toString().padStart(4, "0");

    // Find runs of identical digits
    let runs: number[] = [];
    let i = 0;
    while (i < digits.length) {
      let runLength = 1;
      while (
        i + runLength < digits.length &&
        digits[i] === digits[i + runLength]
      ) {
        runLength++;
      }
      runs.push(runLength);
      i += runLength;
    }
    runs = runs.sort((a, b) => b - a);

    // Classify based on runs
    if (runs[0] === 4) counts[0]++; // Four of a Kind
    else if (runs[0] === 3) counts[1]++; // Three of a Kind
    else if (runs[0] === 2 && runs[1] === 2) counts[2]++; // Two Pairs
    else if (runs[0] === 2) counts[3]++; // One Pair
    else counts[4]++; // No Pattern
  });

  // Calculate chi-square statistic
  const total = data.length;
  const results = patterns.map((pattern, i) => {
    const observed = counts[i];
    const expected = total * pattern.probability;
    const deviation = ((observed - expected) / expected) * 100;

    // Calculate chi-square contribution
    const chiSquare = Math.pow(observed - expected, 2) / expected;

    // Determine status based on deviation
    const status: "PASS" | "WARNING" =
      Math.abs(deviation) > 20 ? "WARNING" : "PASS";

    return {
      pattern: pattern.name,
      observed,
      expected,
      deviation,
      status,
    };
  });

  // Calculate overall chi-square
  const totalChiSquare = results.reduce(
    (sum, r) => sum + Math.pow(r.observed - r.expected, 2) / r.expected,
    0
  );
  const pValue = 1 - normalCDF(Math.sqrt(2 * totalChiSquare) - Math.sqrt(7)); // 4 degrees of freedom

  // Overall status
  const overallStatus: "PASS" | "WARNING" = pValue > 0.05 ? "PASS" : "WARNING";

  return { results, overallStatus };
}

// New helper functions
function calculateRunsTest(sequence: boolean[]): {
  zScore: number;
  pValue: number;
  interpretation: string;
} {
  const n = sequence.length;
  const n1 = sequence.filter((x) => x).length;
  const n2 = n - n1;

  let runs = 1;
  for (let i = 1; i < n; i++) {
    if (sequence[i] !== sequence[i - 1]) runs++;
  }

  const expectedRuns = (2 * n1 * n2) / n + 1;
  const variance = (2 * n1 * n2 * (2 * n1 * n2 - n)) / (n * n * (n - 1));
  const zScore = (runs - expectedRuns) / Math.sqrt(variance);
  const pValue = 2 * (1 - normalCDF(Math.abs(zScore)));

  return {
    zScore,
    pValue,
    interpretation:
      Math.abs(zScore) > 1.96
        ? "Non-random pattern detected (p < 0.05)"
        : "Random pattern confirmed (p >= 0.05)",
  };
}

function calculateAutocorrelation(data: number[], maxLag: number): number[] {
  const n = data.length;
  const mean = data.reduce((a, b) => a + b, 0) / n;
  const variance = data.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / n;

  const autocorr = [];
  for (let lag = 1; lag <= maxLag; lag++) {
    let numerator = 0;
    for (let i = 0; i < n - lag; i++) {
      numerator += (data[i] - mean) * (data[i + lag] - mean);
    }
    autocorr.push(numerator / ((n - lag) * variance));
  }

  return autocorr;
}

function normalCDF(x: number): number {
  // Constants
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;

  // Save the sign of x
  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x);

  // A&S formula 7.1.26
  const t = 1.0 / (1.0 + p * x);
  const y =
    1.0 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

  return 0.5 * (1.0 + sign * y);
}

// Usage
const csvPath = "./fulfillment_output/fulfillment_events.csv";
analyzeFulfillmentData(csvPath);
