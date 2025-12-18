# Port: Docker-Based E2E Harness (Catch Container-Specific Regressions)

## Background (Python v0.1.18)

Python added Docker-based testing to catch container-only failures (notably issue #406):

- `Dockerfile.test` builds an image that:
  - installs Claude Code (`curl https://claude.ai/install.sh | bash`)
  - installs the SDK
  - runs tests in a container
- `scripts/test-docker.sh` runs unit/e2e/all modes
- CI adds a `test-e2e-docker` job that runs e2e tests inside Docker with `ANTHROPIC_API_KEY`

## Why This Matters For Elixir

Elixir’s transports (Port / erlexec / streaming control) depend on OS process semantics.
Historically, container environments surface edge cases:

- PATH differences (CLI discovery)
- permissions/exec bits
- working directory and filesystem behaviors
- stdout/stderr buffering and process lifecycle (early termination symptoms)

Adding a Docker harness provides a cheap “repro environment” that developers and CI can share.

## Port Design (Elixir)

### 1) Add `Dockerfile.test` at repo root

Goals:
- deterministic runtime for `mix test`
- ability to run a small subset of live/integration tests when credentials are provided

Recommended structure:

1. Base image with Erlang/Elixir (pick the repo’s CI versions):
   - `hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-202...` (or similar)
2. Install OS dependencies:
   - `curl`, `git`, `ca-certificates`
3. Install Claude Code CLI:
   - `curl -fsSL https://claude.ai/install.sh | bash`
   - `ENV PATH="/root/.local/bin:$PATH"`
4. Copy repo into container and run:
   - `mix deps.get`
   - `mix compile --warnings-as-errors`
5. Default command:
   - `mix test --exclude requires_cli`

Example skeleton:

```dockerfile
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20241002

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

RUN mix deps.get
RUN mix compile --warnings-as-errors

CMD ["mix", "test", "--exclude", "requires_cli"]
```

### 2) Add `scripts/test-docker.sh`

Mirror Python’s ergonomics:

- `./scripts/test-docker.sh unit`
  - builds image
  - runs `mix test --exclude requires_cli`
- `./scripts/test-docker.sh integration`
  - requires a credential env var (see below)
  - runs `mix test --include integration`
- `./scripts/test-docker.sh all`
  - runs unit first, then integration if credentials exist

Credential environment variable:
- Prefer supporting both:
  - `CLAUDE_AGENT_OAUTH_TOKEN` (CLI OAuth token)
  - `ANTHROPIC_API_KEY` (if the CLI accepts it; the Elixir SDK already passes it through)

### 3) CI wiring (optional but recommended)

Add an additional GitHub Actions job (separate from the main CI job) so it can be gated by secrets:

- `docker-unit` (no secrets)
  - builds `Dockerfile.test`
  - runs unit tests in docker
- `docker-integration` (requires secret)
  - same image, runs `mix test --include integration`
  - uses repository secret `ANTHROPIC_API_KEY` or `CLAUDE_AGENT_OAUTH_TOKEN`

Important: keep the current “pure unit” CI job; Docker is additive, not a replacement.

### 4) Keep integration scope small and purposeful

Rather than running the full integration suite in Docker, target the regressions we care about:

- filesystem agents + setting sources scenario (see `04_filesystem_agents_regression.md`)

This minimizes CI cost and reduces flakiness.

## Proposed Elixir Touchpoints

- New: `Dockerfile.test`
- New: `scripts/test-docker.sh`
- New (optional): `.dockerignore`
- Update (optional): `.github/workflows/elixir.yaml` to add docker unit + docker integration jobs

## Test Plan

- Local:
  - `./scripts/test-docker.sh unit` works without credentials
  - `./scripts/test-docker.sh integration` succeeds when token is provided
- CI:
  - docker unit job always runs
  - docker integration job runs only when secret is configured

## Risks / Open Questions

- Does the official installer allow pinning to `2.0.72`? If not, Docker runs “latest CLI”, which can drift.
  - Mitigation: in Dockerfile, optionally pin via npm when Node is available.
- Running live tests in CI can be costly and flaky.
  - Mitigation: keep the docker integration subset small and put strong timeouts around prompts.
