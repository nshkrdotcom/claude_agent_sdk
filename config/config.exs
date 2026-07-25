import Config

logger_metadata = [
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

# Default configuration.
#
# The Claude model catalog (short forms, full ids, default) is owned by
# `cli_subprocess_core` and read through `ClaudeAgentSDK.Model`; this app
# deliberately ships no `:models` config so a stale local copy cannot drift
# from the shared registry.
config :claude_agent_sdk,
  use_mock: false,
  build_env: config_env(),
  log_level: :warning

# Logger metadata used throughout the SDK (Credo strict compliance).
config :logger, :default_formatter, metadata: logger_metadata

config :logger, :console, metadata: logger_metadata

# Import environment specific config
import_config "#{config_env()}.exs"
