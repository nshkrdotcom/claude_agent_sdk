defmodule Examples.RuntimeControlExamplesTest do
  use ExUnit.Case, async: false

  @scripts [
    {"model switcher", "examples/runtime_control/model_switcher.exs", "Switch confirmed"},
    {"transport swap", "examples/runtime_control/transport_swap.exs", "Transport Swap Demo"},
    {"subscriber broadcast", "examples/runtime_control/subscriber_broadcast.exs",
     "Subscriber Broadcast Demo"}
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
