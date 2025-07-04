# Enable mocking for tests
Application.put_env(:claude_code_sdk, :use_mock, true)

# Start the mock server
{:ok, _} = ClaudeCodeSDK.Mock.start_link()

ExUnit.start()
