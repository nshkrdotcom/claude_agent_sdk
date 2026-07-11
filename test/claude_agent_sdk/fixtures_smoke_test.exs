defmodule ClaudeAgentSDK.FixturesSmokeTest do
  @moduledoc """
  Golden-fixture smoke test for CLI 2.1.207 stream-json frames.

  Every fixture under `test/support/fixtures/cli_2_1_207/` must parse through
  `Message.from_json/1` without crashing, with the full raw frame surviving in
  `.raw` — proving the parser tolerates the new frames before (and after) they
  are typed. Lines starting with `#` are provenance comments (`# SYNTHETIC`
  markers) and are skipped.
  """
  use ClaudeAgentSDK.SupertesterCase, async: true

  alias ClaudeAgentSDK.Message

  @fixtures_dir Path.expand("../support/fixtures/cli_2_1_207", __DIR__)

  defp fixture_frames(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
  end

  for path <-
        Path.wildcard(
          Path.join(Path.expand("../support/fixtures/cli_2_1_207", __DIR__), "*.jsonl")
        ) do
    @path path
    test "fixture #{Path.basename(path)} parses without crashing" do
      frames = fixture_frames(@path)
      assert frames != [], "fixture #{@path} contains no frames"

      for json <- frames do
        raw = Jason.decode!(json)
        assert {:ok, %Message{} = msg} = Message.from_json(json)
        assert msg.raw == raw, "raw frame did not survive round-trip in #{@path}"
      end
    end
  end

  test "fixture directory contains the six minimum frame families" do
    files = @fixtures_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".jsonl"))

    for required <- [
          "result_terminal_reason.jsonl",
          "system_background_tasks_changed.jsonl",
          "command_lifecycle.jsonl",
          "system_init_capabilities.jsonl",
          "control_interrupt_response.jsonl",
          "peer_message_event.jsonl"
        ] do
      assert required in files, "missing golden fixture #{required}"
    end
  end
end
