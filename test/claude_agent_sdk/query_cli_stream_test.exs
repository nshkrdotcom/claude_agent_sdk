defmodule ClaudeAgentSDK.QueryCLIStreamTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.Options
  alias ClaudeAgentSDK.Query.CLIStream

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
    assert "--print" in args
  end

  test "replay-user-messages is opt-in via extra_args" do
    args = CLIStream.__build_args__("hello", %Options{})
    refute "--replay-user-messages" in args

    args_with_flag =
      CLIStream.__build_args__("hello", %Options{extra_args: %{"replay-user-messages" => nil}})

    assert "--replay-user-messages" in args_with_flag
  end

  defp flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end
end
