import Config

# Default configuration
config :claude_agent_sdk,
  use_mock: false

# Logger metadata used throughout the SDK (Credo strict compliance).
config :logger, :console,
  metadata: [
    :behavior,
    :callback_id,
    :cmd,
    :env_keys,
    :error,
    :method,
    :model,
    :mode,
    :payload_preview,
    :pid,
    :prompt_length,
    :reason,
    :request_id,
    :server,
    :subtype,
    :timeout_ms,
    :tool
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
