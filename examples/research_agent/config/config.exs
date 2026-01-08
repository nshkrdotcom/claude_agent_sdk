import Config

# Research Agent configuration
config :research_agent,
  output_dir: "./research_output"

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
