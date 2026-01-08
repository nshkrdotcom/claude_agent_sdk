import Config

# Test configuration
config :logger, level: :warning

config :email_agent,
  database_path: "priv/test_emails.db"
