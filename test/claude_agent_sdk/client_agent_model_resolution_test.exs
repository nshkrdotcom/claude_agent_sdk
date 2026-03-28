defmodule ClaudeAgentSDK.ClientAgentModelResolutionTest do
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.{Agent, Client, Options}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  test "active agent invalidates stale model payload before CLI startup" do
    fake_cli = FakeCLI.new!()

    options =
      Options.new(
        model: "sonnet",
        provider_backend: :anthropic,
        agents: %{
          coder:
            Agent.new(
              description: "Coding agent",
              prompt: "You write code",
              model: "haiku"
            )
        },
        agent: :coder
      )

    {:ok, client} =
      Client.start_link(FakeCLI.options(fake_cli, options))

    on_exit(fn ->
      safe_stop(client)
      FakeCLI.cleanup(fake_cli)
    end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)
    assert {:ok, _request_id} = Client.await_init_sent(client, 1_000)
  end

  defp safe_stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Client.stop(pid)
  catch
    :exit, _ -> :ok
  end
end
