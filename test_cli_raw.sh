#!/bin/bash

echo "Testing claude CLI directly in shell..."
echo "Command: claude --print --output-format stream-json 'Say hi'"
echo "----------------------------------------"

# Run with visible output
claude --print --output-format stream-json "Say hi" 2>&1 | while IFS= read -r line; do
    echo "[$(date +%H:%M:%S)] $line"
done

echo "----------------------------------------"
echo "Exit code: $?"