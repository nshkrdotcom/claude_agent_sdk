#!/usr/bin/env elixir

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))
Code.require_file(Path.expand("support/mock_transport.exs", __DIR__))

alias ClaudeAgentSDK.{Client, Options}
alias ClaudeAgentSDK.Permission.{Context, Result}
alias Examples.Support
alias Examples.Support.MockTransport

Support.ensure_mock!()
Support.header!("Control Client Demo (mock transport, deterministic)")

permission_callback = fn %Context{} = ctx ->
  case ctx.tool_name do
    "Bash" ->
      Result.allow(
        updated_input: %{"command" => "echo ok"},
        updated_permissions: [%{type: "addRules", tool_name: "Bash", behavior: "deny"}]
      )

    _ ->
      Result.allow()
  end
end

options = %Options{permission_mode: :default, can_use_tool: permission_callback}

{:ok, client} =
  Client.start_link(options,
    transport: MockTransport,
    transport_opts: [owner: self()]
  )

transport =
  receive do
    {:mock_transport_started, pid} -> pid
  after
    1_000 -> raise "Timed out waiting for mock transport"
  end

:sys.get_state(client)

request_id = "perm_req_demo"

MockTransport.push_json(transport, %{
  "type" => "control_request",
  "request_id" => request_id,
  "request" => %{
    "subtype" => "can_use_tool",
    "tool_name" => "Bash",
    "input" => %{"command" => "echo hi"},
    "permission_suggestions" => []
  }
})

Process.sleep(50)

response =
  transport
  |> MockTransport.recorded()
  |> Enum.map(&Jason.decode!/1)
  |> Enum.find(fn
    %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
    _ -> false
  end) || raise "Did not record control_response"

IO.inspect(response, label: "control_response")

result = get_in(response, ["response", "result"]) || %{}

unless Map.has_key?(result, "updatedInput") do
  raise "Expected updatedInput camelCase key in response result"
end

unless Map.has_key?(result, "updatedPermissions") do
  raise "Expected updatedPermissions camelCase key in response result"
end

IO.puts("\n✓ Permission response uses camelCase keys")

Client.stop(client)
