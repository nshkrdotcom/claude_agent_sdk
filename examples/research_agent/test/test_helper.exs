# Start ExUnit
ExUnit.start(capture_log: true)

# Configure test environment
Application.put_env(:research_agent, :use_mock, true)
