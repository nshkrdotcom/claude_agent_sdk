defmodule Examples.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @scripts [
    {"control client demo", "examples/archive/mock_demos/control_client_demo.exs",
     "Control Client Demo"},
    {"streaming demo", "examples/archive/mock_demos/streaming_demo.exs", "Streaming Demo"},
    {"sdk mcp demo", "examples/archive/mock_demos/sdk_mcp_demo.exs", "SDK MCP Demo"}
  ]

  for {label, script, expected} <- @scripts do
    @script script
    @expected expected

    test "#{label} example runs successfully" do
      {output, status} = System.cmd("mix", ["run", @script], stderr_to_stdout: true)

      assert status == 0, "mix run #{@script} exited with status #{status}\n#{output}"
      assert output =~ @expected
    end
  end
end
