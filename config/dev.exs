import Config

# Provider-local mocks are package-local test fixtures only. Development should
# use the real CLI path or the shared ASM/cli_subprocess_core simulation path.
config :claude_agent_sdk,
  use_mock: false
