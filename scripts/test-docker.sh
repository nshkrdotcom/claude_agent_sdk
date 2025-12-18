#!/bin/bash
# Run SDK tests in Docker container
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Building Docker test image..."
docker build -f Dockerfile.test -t claude-sdk-elixir-test .

case "${1:-unit}" in
    unit)
        echo "Running unit tests in Docker..."
        docker run --rm claude-sdk-elixir-test mix test
        ;;
    integration)
        if [ -z "$ANTHROPIC_API_KEY" ]; then
            echo "Error: ANTHROPIC_API_KEY required for integration tests"
            exit 1
        fi
        echo "Running integration tests in Docker..."
        docker run --rm -e ANTHROPIC_API_KEY \
            claude-sdk-elixir-test mix test --include integration
        ;;
    all)
        echo "Running all tests in Docker..."
        docker run --rm claude-sdk-elixir-test mix test
        if [ -n "$ANTHROPIC_API_KEY" ]; then
            docker run --rm -e ANTHROPIC_API_KEY \
                claude-sdk-elixir-test mix test --include integration
        fi
        ;;
    *)
        echo "Usage: $0 [unit|integration|all]"
        exit 1
        ;;
esac

echo "Done!"

