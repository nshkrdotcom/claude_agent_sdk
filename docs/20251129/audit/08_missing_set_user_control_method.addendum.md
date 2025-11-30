# Addendum - Missing set_user Runtime Control Method

- **Control protocol support is unproven.** Neither the Python nor Elixir SDKs expose a `set_user` control request, and the CLI docs/code in this repo contain no `set_user` control subtype. The original note about Elixir supporting runtime user switching is likely incorrect.
- **Current Elixir behavior:** The `user` option is applied only when spawning the CLI process to run under an alternate OS account (`lib/claude_agent_sdk/process.ex:125-138`, `lib/claude_agent_sdk/transport/port.ex:280-338`), not dynamically at runtime.
- **Impact on port comparison:** Both SDKs lack runtime user switching; this is a cross-SDK limitation tied to CLI capabilities. If runtime switching is desired, it would require a new CLI control message plus client handling in both languages.
