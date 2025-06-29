#!/bin/bash

# Setup script for erlexec-based Claude Code SDK

echo "Setting up Claude Code SDK with erlexec..."
echo "========================================"

# Install dependencies
echo "1. Installing dependencies..."
mix deps.get

# Compile
echo "2. Compiling..."
mix compile

# Check claude CLI
echo "3. Checking Claude CLI..."
if command -v claude &> /dev/null; then
    echo "✅ Claude CLI found: $(which claude)"
else
    echo "❌ Claude CLI not found"
    echo "   Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Test claude CLI
echo "4. Testing Claude CLI..."
if claude --version &> /dev/null; then
    echo "✅ Claude CLI working"
else
    echo "⚠️  Claude CLI may not be authenticated"
    echo "   Run: claude login"
fi

echo ""
echo "🚀 Setup complete! Run tests with:"
echo "   elixir erlexec_test.exs"