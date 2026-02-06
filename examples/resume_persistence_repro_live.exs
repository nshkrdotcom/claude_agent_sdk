#!/usr/bin/env elixir

# Repro: --print --resume turn persistence gap (LIVE)
#
# This example is intentionally strict: it fails when intermediate turns are not
# persisted across `ClaudeAgentSDK.resume/3` calls.
#
# Run: mix run examples/resume_persistence_repro_live.exs

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options, Session}
alias Examples.Support

Support.ensure_live!()
Support.header!("Resume Persistence Repro (live)")

nonce = System.unique_integer([:positive]) |> Integer.to_string()
token_a = "tokA_#{nonce}_#{System.system_time(:microsecond)}"
token_b = "tokB_#{nonce}_#{System.monotonic_time(:microsecond)}"

options = %Options{
  model: "haiku",
  max_turns: 1,
  output_format: :stream_json,
  allowed_tools: [],
  setting_sources: ["user"]
}

assert_success = fn messages, label ->
  case Enum.find(messages, &(&1.type == :result)) do
    %{subtype: :success} ->
      :ok

    %{subtype: other, data: data} ->
      raise "#{label} did not succeed (result subtype: #{inspect(other)}): #{inspect(data)}"

    nil ->
      raise "#{label} returned no result message."
  end
end

assistant_text = fn messages ->
  messages
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")
end

IO.puts("1) Creating a new session...")

initial =
  ClaudeAgentSDK.query(
    "Reply with exactly READY.",
    options
  )
  |> Enum.to_list()

assert_success.(initial, "initial query")

session_id =
  case Session.extract_session_id(initial) do
    id when is_binary(id) and id != "" -> id
    _ -> raise "No session_id found in initial query response."
  end

IO.puts("   Session: #{session_id}")
IO.puts("2) Turn 2: store token A")

turn_two =
  ClaudeAgentSDK.resume(
    session_id,
    "Store this token for later recall: #{token_a}. Reply exactly STORED_A.",
    options
  )
  |> Enum.to_list()

assert_success.(turn_two, "turn 2")

IO.puts("3) Turn 3: store token B")

turn_three =
  ClaudeAgentSDK.resume(
    session_id,
    "Store this token for later recall: #{token_b}. Reply exactly STORED_B.",
    options
  )
  |> Enum.to_list()

assert_success.(turn_three, "turn 3")

IO.puts("4) Turn 4: ask Claude to recall both prior tokens")

final =
  ClaudeAgentSDK.resume(
    session_id,
    """
    From earlier turns in this same conversation, output both stored tokens exactly.
    Format exactly:
    TOKEN_A=<value>
    TOKEN_B=<value>
    No extra text.
    """,
    options
  )
  |> Enum.to_list()

assert_success.(final, "final recall turn")
final_text = assistant_text.(final)

missing =
  [token_a, token_b]
  |> Enum.reject(&String.contains?(final_text, &1))

if missing != [] do
  raise """
  Repro confirmed: missing recalled token(s): #{Enum.join(missing, ", ")}

  Final assistant output:
  #{final_text}

  This typically indicates that intermediate turns were not persisted across --print --resume calls.
  """
end

IO.puts("✅ Repro did NOT trigger: both tokens were recalled.")
Support.halt_if_runner!()
