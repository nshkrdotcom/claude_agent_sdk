defmodule ClaudeAgentSDK.Options0180Test do
  @moduledoc """
  Section F option additions: include_hook_events, --file resources, structured
  sandbox network config, and session_store_flush.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options

  defp args(opts), do: opts |> Options.new() |> Options.to_args()

  describe "include_hook_events" do
    test "emits --include-hook-events when set" do
      assert "--include-hook-events" in args(include_hook_events: true)
    end

    test "omitted by default" do
      refute "--include-hook-events" in args([])
    end
  end

  describe "file resources" do
    test "emits one --file per resource in file_id:path form" do
      a =
        args(
          files: [
            %{file_id: "file_abc", path: "doc.txt"},
            %{file_id: "file_def", path: "img.png"}
          ]
        )

      assert Enum.chunk_every(a, 2, 1)
             |> Enum.any?(&(&1 == ["--file", "file_abc:doc.txt"]))

      assert Enum.chunk_every(a, 2, 1)
             |> Enum.any?(&(&1 == ["--file", "file_def:img.png"]))
    end

    test "omitted when empty" do
      refute "--file" in args(files: [])
    end
  end

  describe "structured sandbox network config" do
    test "typed snake_case keys are serialized to the CLI camelCase settings JSON" do
      a =
        args(
          sandbox: %{
            enabled: true,
            excluded_commands: ["rm"],
            network: %{
              allowed_domains: ["api.example.com"],
              denied_domains: ["evil.example"],
              allow_managed_domains_only: false,
              http_proxy_port: 8080
            }
          }
        )

      idx = Enum.find_index(a, &(&1 == "--settings"))
      json = Enum.at(a, idx + 1)
      settings = Jason.decode!(json)

      assert settings["sandbox"]["enabled"] == true
      assert settings["sandbox"]["excludedCommands"] == ["rm"]
      assert settings["sandbox"]["network"]["allowedDomains"] == ["api.example.com"]
      assert settings["sandbox"]["network"]["deniedDomains"] == ["evil.example"]
      assert settings["sandbox"]["network"]["allowManagedDomainsOnly"] == false
      assert settings["sandbox"]["network"]["httpProxyPort"] == 8080
    end

    test "already-camelCase maps pass through unchanged (back-compat)" do
      a = args(sandbox: %{"network" => %{"allowedDomains" => ["x.example"]}})
      idx = Enum.find_index(a, &(&1 == "--settings"))
      settings = a |> Enum.at(idx + 1) |> Jason.decode!()
      assert settings["sandbox"]["network"]["allowedDomains"] == ["x.example"]
    end
  end

  describe "session_store_flush" do
    test "defaults to :batched and accepts :eager" do
      assert Options.new([]).session_store_flush in [nil, :batched]
      assert Options.new(session_store_flush: :eager).session_store_flush == :eager
    end

    test "rejects an invalid flush mode" do
      assert_raise ArgumentError, ~r/session_store_flush/, fn ->
        Options.new(session_store_flush: :bogus)
      end
    end
  end
end
