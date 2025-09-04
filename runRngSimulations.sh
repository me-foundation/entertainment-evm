#!/bin/bash

mkdir -p simulations
SEED=10000000
for i in $(seq 1 ${1:-10}); do
  RNG_SEED=$SEED forge test --match-test testRNGOutput --gas-limit 9999999999999999999 &
  SEED=$((SEED + 10000000))
  if [ $((i % 5)) -eq 0 ]; then
    wait
  fi
done
wait

cat simulations/rng_results_*.csv > simulations/rng_all_results.csv
