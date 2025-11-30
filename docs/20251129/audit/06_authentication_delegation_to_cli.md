# Authentication Fully Delegated to CLI

- **What's missing:** The SDK has no explicit authentication provider support. All authentication (Anthropic API key, OAuth, Bedrock, Vertex) is handled entirely by the CLI subprocess via environment variables and CLI configuration.

- **Evidence:**
  - No authentication-related code in `src/claude_agent_sdk/` except for passing env vars

  - `src/claude_agent_sdk/_internal/transport/subprocess_cli.py:307-313`:
    ```python
    # Merge environment variables: system -> user -> SDK required
    process_env = {
        **os.environ,
        **self._options.env,  # User-provided env vars
        "CLAUDE_CODE_ENTRYPOINT": "sdk-py",
        "CLAUDE_AGENT_SDK_VERSION": __version__,
    }
    ```
    Authentication env vars (like `ANTHROPIC_API_KEY`) are passed through `os.environ` or `options.env`

  - `src/claude_agent_sdk/types.py`: No authentication-related options or types

  - E2E tests use environment variables only (`e2e-tests/conftest.py:9-15`):
    ```python
    def api_key():
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            pytest.skip("ANTHROPIC_API_KEY environment variable is required")
    ```

- **Impact:**
  1. **No SDK-level auth validation**: Errors surface only at runtime from CLI
  2. **No programmatic auth switching**: Cannot change auth providers mid-session
  3. **Limited error messages**: Auth failures come as opaque CLI errors
  4. **No auth status introspection**: Cannot check if authenticated before making requests
  5. **Documentation gap**: Users must know to set environment variables correctly

- **Proposed fix:**

  **Option 1: Document Current Behavior (Minimal)**
  - Add clear documentation about supported authentication methods
  - Document required environment variables for each provider
  - Explain how to switch between Anthropic API, OAuth, Bedrock, Vertex

  **Option 2: Add Auth Validation (Medium)**
  - Add optional pre-flight auth validation
  - Check for required env vars before starting subprocess
  - Provide clear error messages about missing configuration

  **Option 3: Add Auth Provider Abstraction (Full)**
  - Add explicit auth options in `ClaudeAgentOptions`
  - Support programmatic auth configuration:
    ```python
    ClaudeAgentOptions(
        auth=AnthropicAuth(api_key="sk-ant-..."),
        # or
        auth=BedrockAuth(region="us-east-1"),
        # or
        auth=VertexAuth(project="my-project"),
    )
    ```
  - Validate auth before starting CLI
  - Provide auth status methods
