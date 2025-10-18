# Enable mocking for tests
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeAgentSDK.Mock.start_link()

# Ensure test support modules are loaded
# This is necessary because elixirc_paths compiles them, but we need to ensure they're loaded
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.CalculatorTools)
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.ErrorTools)
Code.ensure_loaded!(ClaudeAgentSDK.TestSupport.ImageTools)

ExUnit.start()
