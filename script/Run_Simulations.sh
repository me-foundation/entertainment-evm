#!/bin/bash

# Run 1000 simulations in batches of 10
for batch in {1..100}; do
  echo "Starting batch $batch of 100"
  for i in {1..10}; do
    test_num=$(( (batch-1)*10 + i ))
    echo "Starting simulation with SEED=$test_num"
    SEED=$test_num forge test --match-test testSimulatePlay -vv --gas-limit 9999999999999999999 > "./simulations/simulation_$test_num.log" 2>&1 &
  done
  # Wait for current batch to complete before starting next batch
  wait
  echo "Completed batch $batch"
done
  