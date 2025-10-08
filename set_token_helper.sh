#!/bin/bash

# Helper script to set CLAUDE_CODE_OAUTH_TOKEN correctly
# Run with: source set_token_helper.sh

echo "🔐 Setting CLAUDE_CODE_OAUTH_TOKEN"
echo ""
echo "Paste your OAuth token (from 'claude setup-token'):"
read -r TOKEN

# Export the token
export CLAUDE_CODE_OAUTH_TOKEN="$TOKEN"

echo ""
echo "✅ Token set successfully!"
echo ""
echo "Verify:"
echo "  echo \$CLAUDE_CODE_OAUTH_TOKEN | head -c 30"
echo "  # Should show: sk-ant-oat01-..."
echo ""
echo "To make permanent, add to ~/.bashrc:"
echo "  echo 'export CLAUDE_CODE_OAUTH_TOKEN=\"$TOKEN\"' >> ~/.bashrc"
echo ""
echo "Now run: mix run test_live_v0_1_0.exs"
