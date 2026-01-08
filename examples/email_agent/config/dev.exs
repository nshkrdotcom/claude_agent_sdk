import Config

# Development configuration
config :logger, level: :debug

config :email_agent,
  database_path: "priv/emails.db"
