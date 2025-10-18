#!/bin/bash
for example in examples/v0_4_0/*.exs; do
  echo "=== Running $example ==="
  mix run "$example" 2>&1 | tail -5
  echo ""
done
