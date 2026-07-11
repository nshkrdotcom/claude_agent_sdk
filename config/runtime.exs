import Config

# Snapshot only the env vars the SDK actually reads (plus the CLAUDE_ /
# ANTHROPIC_ namespaces) — a whole-System.get_env() copy would spread every
# unrelated secret in the parent environment into inspectable Application
# config (Application.get_all_env/1, :observer, crash dumps).
config :claude_agent_sdk, :env, ClaudeAgentSDK.Config.Env.snapshot(System.get_env())
