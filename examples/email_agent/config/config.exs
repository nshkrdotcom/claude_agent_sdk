import Config

# Email Agent Configuration

config :email_agent,
  database_path: "priv/emails.db",
  rules_file: "priv/rules.json"

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
