#!/bin/bash

# Script to run all examples
# Usage:
#   ./run_all_examples.sh mock    # Safe, no API costs
#   ./run_all_examples.sh live    # Real API calls, costs money

MODE="${1:-mock}"

if [ "$MODE" = "live" ]; then
  echo "⚠️  WARNING: Running in LIVE mode - will make real API calls and incur costs!"
  echo "Press Ctrl+C to cancel, or Enter to continue..."
  read
  RUN_CMD="mix run.live"
else
  echo "✅ Running in MOCK mode - safe, no API costs"
  RUN_CMD="mix run"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            Running All Examples ($MODE mode)                  "
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Counter
SUCCESS=0
FAILED=0

# Run examples from examples/ directory
for file in examples/*.exs; do
  if [ -f "$file" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if $RUN_CMD "$file"; then
      SUCCESS=$((SUCCESS + 1))
      echo "✅ SUCCESS: $file"
    else
      FAILED=$((FAILED + 1))
      echo "❌ FAILED: $file"
    fi
    echo ""
  fi
done

# Run root-level example files
for file in example.exs demo_mock.exs final_test.exs; do
  if [ -f "$file" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if $RUN_CMD "$file"; then
      SUCCESS=$((SUCCESS + 1))
      echo "✅ SUCCESS: $file"
    else
      FAILED=$((FAILED + 1))
      echo "❌ FAILED: $file"
    fi
    echo ""
  fi
done

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                         SUMMARY                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ✅ Successful: $SUCCESS                                         "
echo "║  ❌ Failed:     $FAILED                                         "
echo "╚══════════════════════════════════════════════════════════════╝"
