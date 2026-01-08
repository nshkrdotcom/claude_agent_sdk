import Config

# Test configuration
config :research_agent,
  output_dir: System.tmp_dir!(),
  use_mock: true

# Quieter logging in tests
config :logger, level: :warning
