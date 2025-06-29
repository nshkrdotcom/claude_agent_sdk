#!/bin/bash

# Setup script for Claude Code SDK for Elixir

echo "Claude Code SDK for Elixir - Setup"
echo "=================================="
echo ""

# Check for Elixir
if ! command -v elixir &> /dev/null; then
    echo "❌ Elixir not found. Please install Elixir first."
    echo "   Visit: https://elixir-lang.org/install.html"
    exit 1
fi
echo "✅ Elixir found: $(elixir --version | head -n 1)"

# Check for Mix
if ! command -v mix &> /dev/null; then
    echo "❌ Mix not found. Mix should come with Elixir."
    exit 1
fi
echo "✅ Mix found"

# Check for npm
if ! command -v npm &> /dev/null; then
    echo "❌ npm not found. Please install Node.js/npm first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi
echo "✅ npm found: $(npm --version)"

# Install Claude CLI if not present
if ! command -v claude &> /dev/null; then
    echo ""
    echo "⚠️  Claude CLI not found. Installing..."
    npm install -g @anthropic-ai/claude-code
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install Claude CLI"
        echo "   Try running: sudo npm install -g @anthropic-ai/claude-code"
        exit 1
    fi
else
    echo "✅ Claude CLI found: $(which claude)"
fi

# Check Claude CLI auth status
echo ""
echo "Checking Claude CLI authentication..."
if claude --version &> /dev/null; then
    echo "✅ Claude CLI is accessible"
    echo ""
    echo "ℹ️  This SDK uses your existing Claude CLI authentication."
    echo "   If you haven't authenticated yet, run: claude login"
else
    echo "⚠️  Could not verify Claude CLI status"
    echo "   You may need to run: claude login"
fi

# Install Elixir dependencies
echo ""
echo "Installing Elixir dependencies..."
mix deps.get

# Compile
echo "Compiling..."
mix compile

echo ""
echo "✅ Setup complete!"
echo ""
echo "To test the SDK, run:"
echo "  ./run_test.sh"
echo ""
echo "Or try the example:"
echo "  mix run example.exs"