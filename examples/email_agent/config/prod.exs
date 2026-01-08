import Config

# Production configuration
config :logger, level: :info

config :email_agent,
  database_path: System.get_env("DATABASE_PATH", "priv/emails.db")
