#!/bin/bash
# Test All Examples - Organized by Group
# This script runs all SDK examples to verify they work correctly
#
# Usage:
#   ./test_all_examples.sh [group]
#
# Groups:
#   getting-started  - Quick start examples
#   mcp             - v0.5.0 MCP tools (mock mode only)
#   agents          - v0.4.0 Agents & Permissions (mock mode only)
#   hooks           - v0.3.0 Hooks system
#   core            - Core/basic examples (mock mode only)
#   all             - All mock mode examples (default)
#   live            - DANGEROUS: Runs live examples (costs money!)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Function to run an example
run_example() {
    local name="$1"
    local command="$2"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Running: $name${NC}"
    echo -e "${BLUE}Command: $command${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if eval "$command" 2>&1 | tail -20; then
        echo -e "${GREEN}✅ PASSED: $name${NC}\n"
        ((PASSED++))
    else
        echo -e "${RED}❌ FAILED: $name${NC}\n"
        ((FAILED++))
    fi
}

# Function to skip an example
skip_example() {
    local name="$1"
    local reason="$2"

    echo -e "${YELLOW}⏭️  SKIPPED: $name${NC}"
    echo -e "${YELLOW}   Reason: $reason${NC}\n"
    ((SKIPPED++))
}

# Getting Started Examples
test_getting_started() {
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🎯 Getting Started Examples${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"

    skip_example "Showcase" "Interactive - run manually with 'mix showcase'"
    run_example "SDK MCP Simple Test" "mix run examples/advanced_features/sdk_mcp_simple_test.exs"
}

# v0.5.0 MCP Examples
test_mcp() {
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🌟 v0.5.0 MCP Tools Examples${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"

    run_example "MCP Calculator Tool" "mix run examples/advanced_features/mcp_calculator_tool.exs"
    run_example "SDK MCP Simple Test" "mix run examples/advanced_features/sdk_mcp_simple_test.exs"
    skip_example "SDK MCP Live Demo" "Requires real API - use 'MIX_ENV=test mix run.live examples/advanced_features/sdk_mcp_live_demo.exs'"
}

# v0.4.0 Agents & Permissions Examples
test_agents() {
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🤖 v0.4.0 Agents & Permissions Examples${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"

    run_example "Agent Switching" "mix run examples/advanced_features/agent_switching.exs"
    run_example "Permission Control" "mix run examples/advanced_features/permission_control.exs"
    run_example "Full Feature Showcase" "mix run examples/advanced_features/full_feature_showcase.exs"
    skip_example "Agents Live" "Requires real API"
    skip_example "Permissions Live" "Requires real API"
}

# v0.3.0 Hooks Examples
test_hooks() {
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🪝 v0.3.0 Hooks System Examples${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"

    run_example "Basic Bash Blocking" "mix run examples/hooks/basic_bash_blocking.exs"
    run_example "Complete Workflow" "mix run examples/hooks/complete_workflow.exs"
    run_example "Context Injection" "mix run examples/hooks/context_injection.exs"
    run_example "File Policy Enforcement" "mix run examples/hooks/file_policy_enforcement.exs"
    run_example "Logging and Audit" "mix run examples/hooks/logging_and_audit.exs"
}

# Core Examples
test_core() {
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  📚 Core Examples${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"

    run_example "Basic Example" "mix run examples/basic_example.exs"
    run_example "Factorial Example" "mix run examples/factorial_example.exs"
    run_example "Custom Agents" "mix run examples/custom_agents_example.exs"
    run_example "Model Selection" "mix run examples/model_selection_example.exs"
    run_example "Session Features" "mix run examples/session_features_example.exs"
    run_example "Week 1-2 Showcase" "mix run examples/week_1_2_showcase.exs"
    run_example "Test Auth Detection" "mix run examples/test_auth_detection.exs"

    skip_example "Simple Analyzer (Live)" "Requires real API"
    skip_example "File Reviewer (Live)" "Requires real API"
    skip_example "Simple Batch (Live)" "Requires real API"
    skip_example "Test Generator (Live)" "Requires real API"
    skip_example "Project Assistant (Live)" "Requires real API"
}

# Live Examples (WARNING: Costs money!)
test_live() {
    echo -e "${RED}═══════════════════════════════════════════${NC}"
    echo -e "${RED}  ⚠️  LIVE EXAMPLES - COSTS MONEY!${NC}"
    echo -e "${RED}═══════════════════════════════════════════${NC}\n"

    echo -e "${YELLOW}These examples make REAL API calls and will incur costs.${NC}"
    echo -e "${YELLOW}Press Ctrl+C within 5 seconds to cancel...${NC}\n"
    sleep 5

    run_example "SDK MCP Live Demo" "MIX_ENV=test mix run.live examples/advanced_features/sdk_mcp_live_demo.exs"
    run_example "Agents Live" "MIX_ENV=test mix run.live examples/advanced_features/agents_live.exs"
    run_example "Permissions Live" "MIX_ENV=test mix run.live examples/advanced_features/permissions_live.exs"
    run_example "Simple Analyzer" "mix run.live examples/simple_analyzer.exs lib/claude_agent_sdk.ex"

    echo -e "${YELLOW}⚠️  Stopping live tests early to avoid excessive costs${NC}"
    echo -e "${YELLOW}   Run individual examples manually if needed${NC}\n"
}

# Print summary
print_summary() {
    echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  📊 Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Passed:  $PASSED${NC}"
    echo -e "${RED}❌ Failed:  $FAILED${NC}"
    echo -e "${YELLOW}⏭️  Skipped: $SKIPPED${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}\n"

    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}Some examples failed. Please check the output above.${NC}"
        exit 1
    else
        echo -e "${GREEN}All examples passed! 🎉${NC}"
        exit 0
    fi
}

# Main script
GROUP="${1:-all}"

echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Agent SDK - Example Test Suite   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}\n"

case "$GROUP" in
    getting-started)
        test_getting_started
        ;;
    mcp)
        test_mcp
        ;;
    agents)
        test_agents
        ;;
    hooks)
        test_hooks
        ;;
    core)
        test_core
        ;;
    all)
        test_getting_started
        test_mcp
        test_agents
        test_hooks
        test_core
        ;;
    live)
        test_live
        ;;
    *)
        echo -e "${RED}Unknown group: $GROUP${NC}"
        echo -e "Valid groups: getting-started, mcp, agents, hooks, core, all, live"
        exit 1
        ;;
esac

print_summary
