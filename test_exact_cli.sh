#!/bin/bash

echo "Testing exact CLI command..."
echo "Command: claude --print --output-format stream-json --verbose 'Hi'"
echo ""

# Time the command
time claude --print --output-format stream-json --verbose "Hi" 2>&1

echo ""
echo "Exit code: $?"