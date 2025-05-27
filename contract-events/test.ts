import * as fs from "fs";
import * as path from "path";
import { parse } from "csv-parse/sync";

// Read and process the CSV file
const csvFilePath = path.join(__dirname, "../simulations/combined_results.csv");
const fileContent = fs.readFileSync(csvFilePath, "utf-8");

// Parse CSV content
const records = parse(fileContent, {
  columns: false,
  skip_empty_lines: true,
});

// Extract the boolean column (index 10) and convert to boolean
const columnValues = records.map((row: string[]) => row[10] === "true");

// Find the highest number of consecutive trues
let maxConsecutive = 0;
let currentCount = 0;
for (const value of columnValues) {
  if (value) {
    currentCount++;
    if (currentCount > maxConsecutive) {
      maxConsecutive = currentCount;
    }
  } else {
    currentCount = 0;
  }
}

// Find the highest number of wins in any window of 10,000 plays
const windowSize = 1000;
let maxWinsInWindow = 0;
let currentWins = 0;

// Initialize the first window
for (let i = 0; i < Math.min(windowSize, columnValues.length); i++) {
  if (columnValues[i]) currentWins++;
}
maxWinsInWindow = currentWins;

// Slide the window
for (let i = windowSize; i < columnValues.length; i++) {
  if (columnValues[i - windowSize]) currentWins--;
  if (columnValues[i]) currentWins++;
  if (currentWins > maxWinsInWindow) maxWinsInWindow = currentWins;
}

console.log("Highest number of consecutive trues:", maxConsecutive);
console.log(
  `Highest number of wins in any window of ${windowSize} plays:`,
  maxWinsInWindow
);
