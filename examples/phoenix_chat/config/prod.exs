import Config

# For production, you'd typically configure this at runtime via config/runtime.exs
config :phoenix_chat, PhoenixChatWeb.Endpoint,
  url: [host: "localhost", port: 443, scheme: "https"],
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

# Do not print debug messages in production
config :logger, level: :info
