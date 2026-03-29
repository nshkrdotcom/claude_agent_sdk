defmodule ClaudeAgentSDK.QueryCLIStreamTest do
  use ExUnit.Case, async: false

  alias ClaudeAgentSDK.Errors.CLINotFoundError
  alias ClaudeAgentSDK.Message
  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Query.CLIStream
  alias CliSubprocessCore.TestSupport.FakeSSH

  test "forces stream-json output even when output_format is json" do
    options = %Options{output_format: :json}

    args = CLIStream.__build_args__("hello", options)

    assert flag_value(args, "--output-format") == "stream-json"
  end

  test "preserves json-schema flag while enforcing stream-json output" do
    schema = %{"type" => "object", "properties" => %{"foo" => %{"type" => "string"}}}
    options = %Options{output_format: {:json_schema, schema}}

    args = CLIStream.__build_args__("hello", options)

    assert flag_value(args, "--output-format") == "stream-json"

    json_schema_value = flag_value(args, "--json-schema")
    assert Jason.decode!(json_schema_value) == schema
  end

  test "includes stream-json input format for enumerable prompts" do
    args = CLIStream.__build_args__([%{"type" => "user"}], %Options{})

    assert flag_value(args, "--input-format") == "stream-json"
    refute "--print" in args
  end

  test "replay-user-messages is opt-in via extra_args" do
    args = CLIStream.__build_args__("hello", %Options{})
    refute "--replay-user-messages" in args

    args_with_flag =
      CLIStream.__build_args__("hello", %Options{extra_args: %{"replay-user-messages" => nil}})

    assert "--replay-user-messages" in args_with_flag
  end

  test "default built-in transport uses the shared core transport lane" do
    script =
      create_test_script("""
      echo '{"type":"assistant","message":{"role":"assistant","content":"hello"},"session_id":"sess"}'
      """)

    stream = CLIStream.stream_args([], %Options{executable: script})

    assert [%Message{type: :assistant}] = Enum.take(stream, 1)
  end

  test "remote missing Claude CLIs surface a structured error result instead of an empty stream" do
    fake_ssh = FakeSSH.new!()

    try do
      stream =
        CLIStream.stream_args([], %Options{
          executable: "claude-code",
          execution_surface: [
            surface_kind: :static_ssh,
            transport_options:
              FakeSSH.transport_options(fake_ssh, destination: "claude-stream.missing.example")
          ],
          env: %{"PATH" => "/nonexistent_dir_only"}
        })

      assert [%Message{type: :result, subtype: :error_during_execution, data: data}] =
               Enum.to_list(stream)

      assert data.error =~ "remote target claude-stream.missing.example"
      assert %CLINotFoundError{} = data.error_struct
      assert data.error_details[:kind] == :cli_not_found
      assert data.error_details[:exit_code] == 127
    after
      FakeSSH.cleanup(fake_ssh)
    end
  end

  defp flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp create_test_script(body) do
    dir =
      Path.join(System.tmp_dir!(), "query_cli_stream_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "query_cli_stream_test.sh")

    File.write!(path, """
    #!/usr/bin/env bash
    set -euo pipefail
    #{body}
    """)

    File.chmod!(path, 0o755)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)

    path
  end
end
