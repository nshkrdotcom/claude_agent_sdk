import Config

# Default configuration
config :claude_agent_sdk,
  use_mock: false,
  build_env: config_env(),
  log_level: :warning

# Logger metadata used throughout the SDK (Credo strict compliance).
config :logger, :console,
  metadata: [
    :behavior,
    :buffer_limit,
    :callback_id,
    :cmd,
    :dropped,
    :env_keys,
    :error,
    :method,
    :model,
    :mode,
    :payload_preview,
    :pid,
    :prompt_length,
    :prompt_type,
    :reason,
    :request_id,
    :server,
    :subtype,
    :timeout_ms,
    :type,
    :tool
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
