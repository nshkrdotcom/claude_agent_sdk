#!/bin/bash

# Simple test runner for the Claude Code SDK

echo "Claude Code SDK for Elixir - Test Runner"
echo "========================================"

# Check if claude CLI is installed
if ! command -v claude &> /dev/null; then
    echo "❌ Error: Claude CLI not found"
    echo "Please install it with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Note about authentication
echo "ℹ️  Using existing Claude CLI authentication"
echo "   If not authenticated, run: claude login"

echo "✅ Prerequisites checked"
echo ""

# Get dependencies
echo "Installing dependencies..."
mix deps.get

# Compile the project
echo "Compiling..."
mix compile

# Run the basic test
echo ""
echo "Running basic test..."
elixir -pa _build/dev/lib/claude_code_sdk/ebin -pa _build/dev/lib/jason/ebin test_basic.exs