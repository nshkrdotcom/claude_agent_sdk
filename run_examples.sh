#!/bin/bash
for example in examples/advanced_features/*.exs; do
  echo "=== Running $example ==="
  mix run "$example" 2>&1 | tail -5
  echo ""
done
