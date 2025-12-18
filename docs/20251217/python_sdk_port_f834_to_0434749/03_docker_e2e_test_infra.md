# Port: Docker-Based E2E Harness (Catch Container-Specific Regressions)

## Background (Python v0.1.18, commit a0ce44a)

Python added Docker-based testing to catch container-only failures (notably issue #406):

- `Dockerfile.test` (29 lines) builds an image that:
  - Uses `python:3.12-slim` base
  - Installs Claude Code via `curl -fsSL https://claude.ai/install.sh | bash`
  - Installs SDK with `pip install -e ".[dev]"`
  - Verifies CLI with `claude -v`
- `scripts/test-docker.sh` (77 lines) provides unit/e2e/all modes
- `.github/workflows/test.yml` adds `test-e2e-docker` job that runs e2e tests with `ANTHROPIC_API_KEY`
- `.dockerignore` (49 lines) excludes `.git`, `__pycache__`, virtual envs, etc.

## Why This Matters For Elixir

Elixir's transports (Port / erlexec / streaming control) depend on OS process semantics.
Container environments surface edge cases:

- PATH differences (CLI discovery)
- Permissions/exec bits
- Working directory and filesystem behaviors
- stdout/stderr buffering and process lifecycle (early termination symptoms)

A Docker harness provides a reproducible "repro environment" that developers and CI can share.

## Port Design (Elixir)

### 1) Add `Dockerfile.test` at repo root

Goals:
- Deterministic runtime for `mix test`
- Ability to run integration tests when credentials are provided

Use CI versions from `.github/workflows/elixir.yaml` (currently Elixir 1.18.3, OTP 27.3.3).

```dockerfile
# Dockerfile.test - Run SDK tests in containerized environment
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20241016

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /app
COPY . .

# Install dependencies and compile
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get
RUN mix compile --warnings-as-errors

# Verify CLI installation
RUN claude -v

# Default: run unit tests (excludes integration/live/requires_cli)
CMD ["mix", "test"]
```

**Note on test exclusions:** The default `mix test` already excludes `:integration` and `:live` tags via `test/test_helper.exs:17`. The CI also adds `--exclude requires_cli`.

### 2) Add `scripts/test-docker.sh`

```bash
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
    *)
        echo "Usage: $0 [unit|integration]"
        exit 1
        ;;
esac

echo "Done!"
```

### 3) Add `.dockerignore`

```dockerignore
.git
_build
deps
cover
.elixir_ls
*.beam
*.ez
*.log
.DS_Store
priv/_bundled/
```

### 4) CI wiring (optional)

Add to `.github/workflows/elixir.yaml`:

```yaml
  test-docker:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker test image
        run: docker build -f Dockerfile.test -t claude-sdk-test .
      - name: Run unit tests in Docker
        run: docker run --rm claude-sdk-test mix test
```

Integration tests in CI require secrets and are optional.

## Proposed Elixir Touchpoints

| File | Change | Priority |
|------|--------|----------|
| `Dockerfile.test` | Docker test image | Required |
| `scripts/test-docker.sh` | Test runner script | Required |
| `.dockerignore` | Exclude build artifacts | Required |
| `.github/workflows/elixir.yaml` | Docker CI job | Optional |

## Test Plan

| Test | What it verifies |
|------|------------------|
| `./scripts/test-docker.sh unit` | Unit tests pass in container |
| `./scripts/test-docker.sh integration` | Integration tests pass with API key |
| Docker build succeeds | CLI installs correctly in container |

## Risks / Open Questions

1. **CLI version drift** - The installer installs latest CLI, not a pinned version. For reproducibility, could add npm approach in Dockerfile:
   ```dockerfile
   RUN apt-get install -y nodejs npm && npm install -g @anthropic-ai/claude-code@2.0.72
   ```

2. **CI cost** - Integration tests use API credits. Keep scope minimal (filesystem agents regression only).

3. **Base image updates** - Track hexpm/elixir releases to keep image current with CI versions.
