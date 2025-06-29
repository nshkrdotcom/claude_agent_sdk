#!/bin/bash

# Compile and run the quick test

cd "$(dirname "$0")"

echo "Compiling SDK..."
mix deps.get
mix compile

echo -e "\nRunning quick test...\n"

# Run with compiled modules
elixir -pa _build/dev/lib/*/ebin quick_test.exs