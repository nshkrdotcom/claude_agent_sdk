#!/usr/bin/env elixir

# Example: Session features (LIVE)
#
# Demonstrates:
#   - Capturing a real `session_id`
#   - Persisting session transcripts (SessionStore)
#   - Searching/listing saved sessions
#   - Resuming the same session
#   - CLI flag parity for --fork-session, --add-dir, --strict-mcp-config
#
# Run: mix run examples/session_features_example.exs

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias ClaudeAgentSDK.{ContentExtractor, Options, Session, SessionStore}
alias Examples.Support

Support.ensure_live!()
Support.header!("Session Features Example (live)")

storage_dir = Path.join(Support.output_dir!(), "sessions")
File.mkdir_p!(storage_dir)

{:ok, _pid} =
  case SessionStore.start_link(storage_dir: storage_dir) do
    {:ok, pid} -> {:ok, pid}
    {:error, {:already_started, pid}} -> {:ok, pid}
    other -> other
  end

base_options = %Options{
  model: "haiku",
  max_turns: 1,
  output_format: :stream_json,
  allowed_tools: []
}

prompt = "In one sentence, suggest a feature name for a tiny Elixir SDK demo."
messages = ClaudeAgentSDK.query(prompt, base_options) |> Enum.to_list()

assistant_text =
  messages
  |> Enum.filter(&(&1.type == :assistant))
  |> Enum.map(&ContentExtractor.extract_text/1)
  |> Enum.reject(&(&1 in [nil, ""]))
  |> Enum.join("\n")

IO.puts("Prompt: #{prompt}\n")
if assistant_text != "", do: IO.puts("Assistant:\n#{assistant_text}\n")

session_id = Session.extract_session_id(messages)

case session_id do
  id when is_binary(id) and id != "" ->
    IO.puts("Session id: #{id}\n")

    :ok =
      SessionStore.save_session(id, messages,
        tags: ["examples", "session"],
        description: "Live SessionStore example"
      )

    IO.puts("Saved session under: #{storage_dir}\n")

    results = SessionStore.search(tags: ["examples"])
    IO.puts("Search by tag \"examples\": found #{length(results)} session(s)\n")

    IO.puts("Most recent sessions (up to 5):")

    SessionStore.list_sessions()
    |> Enum.take(5)
    |> Enum.each(fn meta ->
      # Handle both atom and string keys for backward compatibility
      sid = meta[:session_id] || meta["session_id"] || "unknown"
      tags = meta[:tags] || meta["tags"] || []
      IO.puts("  - #{sid} (tags: #{inspect(tags)})")
    end)

    IO.puts("\nResuming the same session (no tools)...\n")

    resumed =
      ClaudeAgentSDK.resume(
        id,
        "Now reply with a different one-sentence feature name.",
        base_options
      )
      |> Enum.to_list()

    resumed_text =
      resumed
      |> Enum.filter(&(&1.type == :assistant))
      |> Enum.map(&ContentExtractor.extract_text/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")

    if resumed_text != "", do: IO.puts("Assistant:\n#{resumed_text}\n")

    fork_opts = %Options{base_options | fork_session: true}

    IO.puts("CLI args for --fork-session:")
    IO.inspect(Enum.filter(Options.to_args(fork_opts), &(&1 == "--fork-session")))

  _ ->
    IO.puts("No session_id detected; SessionStore demo skipped.")
end

IO.puts("\nOther session-related CLI flags:")

add_dir_opts =
  %Options{
    base_options
    | add_dir: ["/tmp/project1", "/tmp/project2"],
      allowed_tools: ["Read"]
  }

IO.inspect(
  Enum.filter(
    Options.to_args(add_dir_opts),
    &(String.starts_with?(&1, "/tmp") or &1 == "--add-dir")
  ),
  label: "--add-dir args"
)

mcp_opts = %Options{base_options | mcp_config: "mcp_config.json", strict_mcp_config: true}

IO.inspect(Enum.filter(Options.to_args(mcp_opts), &String.contains?(&1, "mcp")),
  label: "MCP args"
)

IO.puts("\nDone.")
Support.halt_if_runner!()
