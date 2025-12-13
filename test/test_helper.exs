live_tests? = System.get_env("LIVE_TESTS") == "true"

# Enable mocking for tests unless we're explicitly running in live mode.
Application.put_env(:claude_agent_sdk, :use_mock, !live_tests?)

# Start the mock server only when mock mode is enabled.
unless live_tests? do
  {:ok, _} = ClaudeAgentSDK.Mock.start_link()
end

# Ensure test support modules are loaded
# This is necessary because elixirc_paths compiles them, but we need to ensure they're loaded
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.CalculatorTools)
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.ErrorTools)
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.ImageTools)

ExUnit.start(exclude: [:integration, :live])
