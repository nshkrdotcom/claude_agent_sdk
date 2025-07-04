.PHONY: test deps clean docs install example check

# Default target
all: deps test

# Install dependencies
deps:
	mix deps.get

# Run tests
test: deps
	mix test

# Run basic functionality test
check:
	elixir test_basic.exs

# Run example
example:
	elixir example.exs

# Generate documentation
docs:
	mix docs

# Clean build artifacts
clean:
	mix clean
	rm -rf _build deps doc

# Install claude CLI (requires npm)
install-cli:
	npm install -g @anthropic-ai/claude-code

# Check environment
env-check:
	@echo "Checking environment..."
	@command -v claude >/dev/null 2>&1 && echo "✅ Claude CLI installed" || echo "❌ Claude CLI not found"
	@echo "ℹ️  Using existing Claude CLI authentication"
	@echo "   If not authenticated, run: claude login"