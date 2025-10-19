# Migration Guide – v0.4.x → v0.5.0

This document helps maintainers upgrade to the runtime-control release. Follow the checklist to ensure a smooth transition.

## What's New

- Runtime model switching via `ClaudeAgentSDK.Client.set_model/2`
- Transport abstraction (`ClaudeAgentSDK.Transport` behaviour and `transport` option in `Client.start_link/2`)
- Deterministic test tooling powered by `Supertester`

## Upgrade Checklist

1. **Update Dependencies**
   ```elixir
   {:claude_agent_sdk, \"~> 0.5.0\"}
   {:supertester, \"~> 0.2.1\", only: :test}
   ```
2. **Compile & Run Tests**
   Ensure `mix compile` and `mix test` pass before making runtime changes.

3. **Handle `Client.start_link/2` Options**
   - Existing calls that only pass `%Options{}` continue to use the port transport.
   - To inject a custom transport:
     ```elixir
     Client.start_link(options,
       transport: MyApp.Transport.Module,
       transport_opts: [...]
     )
     ```

4. **Adopt Runtime Model Switching (Optional)**
   Replace any client restart logic with `Client.set_model/2`:
   ```elixir
   :ok = Client.set_model(client_pid, \"opus\")
   ```

5. **Update Tests**
   - Use `ClaudeAgentSDK.SupertesterCase` in place of `ExUnit.Case`.
   - Swap fragile timing logic for `SupertesterCase.eventually/2`.
   - Inject `ClaudeAgentSDK.TestSupport.MockTransport` to simulate CLI messages.

6. **Transport Implementers**
   - Implement the new behaviour (`start_link/1`, `send/2`, `subscribe/2`, `close/1`, `status/1`).
   - Ensure newline-terminated JSON payloads.
   - Provide a deterministic test double if your transport talks to external services.

## Breaking Changes

| Area | Description | Mitigation |
|------|-------------|------------|
| `Client.start_link/1` private signature | The implementation now expects a tuple `{options, opts}` internally. Public API remains backward compatible unless you relied on private behaviour. | Call `Client.start_link/2` formally; avoid bypassing the public function. |
| Control protocol | `Protocol.encode_initialize_request/3` is unchanged, but responses now track pending model change requests. | None required. |

## Recommended Test Refactors

- Replace manual `Process.sleep/1` calls with `SupertesterCase.eventually/2`.
- Use the mock transport to assert on control frames:
  ```elixir
  assert_receive {:mock_transport_send, json}
  assert Jason.decode!(json)[\"request\"][\"subtype\"] == \"set_model\"
  ```

## Post-Upgrade Verification

- Run the integration tests (`test/integration/*.exs`) to validate transport/message flow.
- Confirm that your production transport returns `:connected` from `status/1`.
- Exercise the CLI manually to ensure `set_model` behaves as expected.

## Need Help?

File an issue at [GitHub](https://github.com/nshkrdotcom/claude_agent_sdk) or reach out in the discussion board. Contributions to the documentation are always welcome.
