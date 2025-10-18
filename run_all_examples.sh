#!/bin/bash

# Script to run all examples
# Usage:
#   ./run_all_examples.sh         # Safe, no API costs (mock mode)
#   ./run_all_examples.sh mock    # Safe, no API costs (explicit)
#   ./run_all_examples.sh live    # Real API calls, costs money

MODE="${1:-mock}"

if [ "$MODE" = "live" ]; then
  echo ""
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║                    ⚠️  DANGER ZONE ⚠️                          ║"
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  Running in LIVE mode will:                                   ║"
  echo "║  • Make REAL API calls to Claude                              ║"
  echo "║  • Incur REAL costs on your account                           ║"
  echo "║  • Process ~20-30 examples (could be expensive!)              ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  echo ""
  echo -n "Are you SURE you want to continue? [y/N]: "
  read -r response

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled. Run './run_all_examples.sh mock' for safe testing."
    exit 0
  fi

  echo ""
  echo "🔴 Proceeding with LIVE mode..."
  RUN_CMD="MIX_ENV=test mix run.live"
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

# Function to run a single example
run_example() {
  local file="$1"
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
}

# Run examples from examples/ root directory
echo "📁 Core Examples"
echo ""
for file in examples/*.exs; do
  [ -f "$file" ] && run_example "$file"
done

# Run examples from examples/hooks/
echo ""
echo "📁 Hooks Examples"
echo ""
for file in examples/hooks/*.exs; do
  [ -f "$file" ] && run_example "$file"
done

# Run examples from examples/advanced_features/
echo ""
echo "📁 Advanced Features Examples"
echo ""
for file in examples/advanced_features/*.exs; do
  [ -f "$file" ] && run_example "$file"
done

# Run root-level example files (if they exist)
if [ -f "example.exs" ] || [ -f "demo_mock.exs" ] || [ -f "final_test.exs" ]; then
  echo ""
  echo "📁 Root-Level Examples"
  echo ""
  for file in example.exs demo_mock.exs final_test.exs; do
    [ -f "$file" ] && run_example "$file"
  done
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                         SUMMARY                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ✅ Successful: $SUCCESS                                         "
echo "║  ❌ Failed:     $FAILED                                         "
echo "╚══════════════════════════════════════════════════════════════╝"
