# Enable mocking for tests
Application.put_env(:claude_agent_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeAgentSDK.Mock.start_link()

ExUnit.start()
