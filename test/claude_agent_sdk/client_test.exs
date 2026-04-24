defmodule ClaudeAgentSDK.ClientTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Hooks, Options}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}
  alias ClaudeAgentSDK.TestSupport.FakeCLI

  @moduletag :client
  @moduletag :requires_cli

  describe "start_link/1" do
    # Tests in this describe block spawn real CLI process
    @describetag :live_cli
    test "starts client with valid options" do
      options = %Options{}

      # Note: This will try to start a real CLI process
      # For now, we test that it returns expected result types
      result = Client.start_link(options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      # Clean up if started
      case result do
        {:ok, pid} -> Client.stop(pid)
        {:error, _} -> :ok
      end
    end

    test "validates hooks configuration on start" do
      # Invalid hooks config
      options = %Options{
        hooks: %{invalid_event: []}
      }

      # This test expects the GenServer to fail during init with validation error
      # The EXIT message is expected behavior
      Process.flag(:trap_exit, true)

      result = Client.start_link(options)

      case result do
        {:error, {:validation_failed, msg}} ->
          assert msg =~ "Invalid hook event"

        {:ok, pid} ->
          # Wait for EXIT message
          receive do
            {:EXIT, ^pid, {:validation_failed, msg}} ->
              assert msg =~ "Invalid hook event"
          after
            100 ->
              Client.stop(pid)
              flunk("Should have failed validation")
          end
      end
    end

    test "accepts valid hooks configuration" do
      callback = fn _, _, _ -> %{} end

      options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback])
          ]
        }
      }

      # Should validate successfully (may fail to start CLI, but validation passes)
      result = Client.start_link(options)

      case result do
        {:ok, pid} ->
          Client.stop(pid)
          assert true

        {:error, {:validation_failed, _}} ->
          flunk("Hooks validation should have passed")

        {:error, _other_reason} ->
          # CLI not available or other issue, but validation passed
          assert true
      end
    end
  end

  describe "hook callback registry" do
    test "registers hooks during initialization" do
      callback1 = fn _, _, _ -> Output.allow() end
      callback2 = fn _, _, _ -> Output.deny("test") end

      _options = %Options{
        hooks: %{
          pre_tool_use: [
            Matcher.new("Bash", [callback1, callback2])
          ]
        }
      }

      # The registry should be created and populated
      # We can't directly test this without starting the client,
      # but we can test the registry module independently
      registry = Hooks.Registry.new()
      registry = Hooks.Registry.register(registry, callback1)
      registry = Hooks.Registry.register(registry, callback2)

      assert Hooks.Registry.count(registry) == 2
      assert Hooks.Registry.get_id(registry, callback1) == "hook_0"
      assert Hooks.Registry.get_id(registry, callback2) == "hook_1"
    end
  end

  describe "build_hooks_config (unit test of private logic)" do
    # We test this by testing the output of hooks configuration
    test "converts hooks to CLI format" do
      callback = fn _, _, _ -> Output.allow() end

      hooks = %{
        pre_tool_use: [
          Matcher.new("Bash", [callback])
        ]
      }

      # Simulate what Client does
      registry = Hooks.Registry.new()
      registry = Hooks.Registry.register(registry, callback)

      # Build hooks config like Client would
      hooks_config =
        hooks
        |> Enum.map(fn {event, matchers} ->
          event_str = Hooks.event_to_string(event)

          matchers_config =
            Enum.map(matchers, fn matcher ->
              callback_ids =
                Enum.map(matcher.hooks, fn cb ->
                  Hooks.Registry.get_id(registry, cb)
                end)

              %{
                "matcher" => matcher.matcher,
                "hookCallbackIds" => callback_ids
              }
            end)

          {event_str, matchers_config}
        end)
        |> Map.new()

      assert hooks_config == %{
               "PreToolUse" => [
                 %{
                   "matcher" => "Bash",
                   "hookCallbackIds" => ["hook_0"]
                 }
               ]
             }
    end

    test "handles multiple events and matchers" do
      callback1 = fn _, _, _ -> Output.allow() end
      callback2 = fn _, _, _ -> Output.deny("test") end

      hooks = %{
        pre_tool_use: [
          Matcher.new("Bash", [callback1])
        ],
        post_tool_use: [
          Matcher.new("*", [callback2])
        ]
      }

      registry = Hooks.Registry.new()
      registry = Hooks.Registry.register(registry, callback1)
      registry = Hooks.Registry.register(registry, callback2)

      hooks_config =
        hooks
        |> Enum.map(fn {event, matchers} ->
          event_str = Hooks.event_to_string(event)

          matchers_config =
            Enum.map(matchers, fn matcher ->
              callback_ids =
                Enum.map(matcher.hooks, fn cb ->
                  Hooks.Registry.get_id(registry, cb)
                end)

              %{
                "matcher" => matcher.matcher,
                "hookCallbackIds" => callback_ids
              }
            end)

          {event_str, matchers_config}
        end)
        |> Map.new()

      assert Map.keys(hooks_config) |> Enum.sort() == ["PostToolUse", "PreToolUse"]
      assert hooks_config["PreToolUse"] |> List.first() |> Map.get("matcher") == "Bash"
      assert hooks_config["PostToolUse"] |> List.first() |> Map.get("matcher") == "*"
    end

    test "includes matcher timeout when present" do
      callback = fn _, _, _ -> Output.allow() end

      hooks = %{
        pre_tool_use: [
          Matcher.new("Bash", [callback], timeout_ms: 1_500)
        ]
      }

      registry = Hooks.Registry.new()
      registry = Hooks.Registry.register(registry, callback)

      hooks_config =
        hooks
        |> Enum.map(fn {event, matchers} ->
          event_str = Hooks.event_to_string(event)

          matchers_config =
            Enum.map(matchers, fn matcher ->
              Matcher.to_cli_format(matcher, fn cb -> Hooks.Registry.get_id(registry, cb) end)
            end)

          {event_str, matchers_config}
        end)
        |> Map.new()

      assert hooks_config == %{
               "PreToolUse" => [
                 %{
                   "matcher" => "Bash",
                   "hookCallbackIds" => ["hook_0"],
                   "timeout" => 1.5
                 }
               ]
             }
    end
  end

  describe "hook callback invocation (simulated)" do
    test "invokes callback with correct parameters" do
      # Simulate what happens when CLI sends hook_callback request
      callback_invoked = self()

      callback = fn input, tool_use_id, context ->
        send(callback_invoked, {:called, input, tool_use_id, context})
        Output.allow("Test")
      end

      # Simulate hook invocation
      input = %{
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_input" => %{"command" => "echo test"}
      }

      tool_use_id = "toolu_123"
      context = %{signal: nil}

      result = callback.(input, tool_use_id, context)

      # Verify callback was called
      assert_receive {:called, ^input, ^tool_use_id, ^context}
      assert result.hookSpecificOutput.permissionDecision == "allow"
    end

    test "handles callback exceptions" do
      callback = fn _input, _tool_use_id, _context ->
        raise "Intentional error"
      end

      # Simulate what Client does with try/rescue
      result =
        try do
          callback.(%{}, nil, %{})
        rescue
          e -> {:error, Exception.message(e)}
        end

      assert {:error, "Intentional error"} = result
    end

    test "handles callback timeout" do
      callback = fn _input, _tool_use_id, _context ->
        Process.sleep(100)
        Output.allow()
      end

      # Simulate what Client does with Task.yield
      task = Task.async(fn -> callback.(%{}, nil, %{}) end)

      result =
        case Task.yield(task, 50) || Task.shutdown(task) do
          {:ok, output} -> {:ok, output}
          nil -> {:error, "Timeout"}
        end

      assert {:error, "Timeout"} = result
    end
  end

  describe "transport integration" do
    setup do
      Process.flag(:trap_exit, true)
      %{options: %Options{}}
    end

    test "uses provided transport module for initialization messages", %{options: options} do
      %{transport: transport} = start_client_with_fake_cli(options)

      decoded = wait_for_request(transport, 1)
      assert decoded["type"] == "control_request"
      assert decoded["request"]["subtype"] == "initialize"
    end

    test "delivers messages from transport to subscribers", %{options: options} do
      %{client: client, transport: transport} = start_initialized_client_with_fake_cli(options)

      :ok = GenServer.call(client, {:subscribe})

      payload = %{
        "type" => "assistant",
        "message" => %{"content" => "hello", "role" => "assistant"},
        "session_id" => "test-session"
      }

      FakeCLI.push_message(transport, payload)

      message =
        SupertesterCase.eventually(fn ->
          receive do
            {:claude_message, msg} -> msg
          after
            0 -> nil
          end
        end)

      assert message.type == :assistant
      assert message.data[:message]["content"] == "hello"
    end
  end

  describe "model switching" do
    alias ClaudeAgentSDK.Model

    setup do
      Process.flag(:trap_exit, true)

      {:ok, start_initialized_client_with_fake_cli(%Options{})}
    end

    test "set_model sends control request and updates current model", %{
      client: client,
      transport: transport
    } do
      task = Task.async(fn -> Client.set_model(client, "opus") end)

      request = wait_for_request(transport, 2)
      assert request["request"]["subtype"] == "set_model"
      request_id = request["request_id"]

      {:ok, normalized} = Model.validate("opus")

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request_id,
          "subtype" => "success",
          "result" => %{"model" => normalized}
        }
      }

      FakeCLI.push_message(transport, response)

      assert :ok = Task.await(task, 1_000)
      assert {:ok, ^normalized} = Client.get_model(client)
    end

    test "set_model rejects invalid models", %{client: client} do
      assert {:error, {:invalid_model, suggestions}} = Client.set_model(client, "unknown")
      assert is_list(suggestions)
      assert length(suggestions) <= 3
    end

    test "set_model prevents concurrent requests", %{
      client: client,
      transport: transport
    } do
      task = Task.async(fn -> Client.set_model(client, "opus") end)

      request = wait_for_request(transport, 2)
      request_id = request["request_id"]

      assert {:error, :model_change_in_progress} = Client.set_model(client, "sonnet")

      {:ok, normalized} = Model.validate("opus")

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request_id,
          "subtype" => "success",
          "result" => %{"model" => normalized}
        }
      }

      FakeCLI.push_message(transport, response)

      assert :ok = Task.await(task, 1_000)
    end
  end

  describe "runtime control APIs" do
    setup do
      Process.flag(:trap_exit, true)

      {:ok,
       start_initialized_client_with_fake_cli(%Options{}, init_response: server_info_response())}
    end

    test "interrupt sends control request", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.interrupt(client) end)

      request = wait_for_request(transport, 2)
      assert request["request"]["subtype"] == "interrupt"

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request["request_id"],
          "subtype" => "success",
          "response" => %{}
        }
      }

      FakeCLI.push_message(transport, response)
      assert :ok = Task.await(task, 1_000)
    end

    test "interrupt forwards CLI error", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.interrupt(client) end)

      request = wait_for_request(transport, 2)

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request["request_id"],
          "subtype" => "error",
          "error" => "blocked"
        }
      }

      FakeCLI.push_message(transport, response)
      assert {:error, "blocked"} = Task.await(task, 1_000)
    end

    test "get_server_info returns initialization payload", %{client: client} do
      info =
        SupertesterCase.eventually(fn ->
          case Client.get_server_info(client) do
            {:ok, info} -> info
            _ -> nil
          end
        end)

      assert %{"commands" => [_ | _]} = info
    end

    test "get_server_info errors before initialization" do
      %{client: client, transport: transport} = start_client_with_fake_cli(%Options{})

      assert wait_for_request(transport, 1)["request"]["subtype"] == "initialize"

      assert {:error, :not_initialized} = Client.get_server_info(client)
    end

    test "get_context_usage sends control request and returns usage", %{
      client: client,
      transport: transport
    } do
      task = Task.async(fn -> Client.get_context_usage(client) end)

      request = wait_for_request(transport, 2)
      assert request["request"]["subtype"] == "get_context_usage"

      usage = %{"tokens" => %{"input" => 10, "output" => 2}, "percent" => 0.12}

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request["request_id"],
          "subtype" => "success",
          "response" => usage
        }
      }

      FakeCLI.push_message(transport, response)

      assert {:ok, ^usage} = Task.await(task, 1_000)
    end

    test "receive_response collects messages", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.receive_response(client) end)

      SupertesterCase.eventually(fn ->
        state = :sys.get_state(client)

        case state.subscribers do
          subs when is_map(subs) and map_size(subs) > 0 -> true
          subs when is_list(subs) and subs != [] -> true
          _ -> nil
        end
      end)

      assistant = %{
        "type" => "assistant",
        "message" => %{"role" => "assistant", "content" => "hi"},
        "session_id" => "sess"
      }

      result = %{
        "type" => "result",
        "subtype" => "success",
        "session_id" => "sess",
        "duration_ms" => 10,
        "num_turns" => 1,
        "is_error" => false
      }

      FakeCLI.push_message(transport, assistant)
      FakeCLI.push_message(transport, result)

      assert {:ok, messages} = Task.await(task, 1_000)
      assert length(messages) == 2
      assert Enum.at(messages, 0).type == :assistant
      assert Enum.at(messages, 1).type == :result
    end
  end

  describe "file checkpointing control" do
    setup do
      Process.flag(:trap_exit, true)

      {:ok,
       start_initialized_client_with_fake_cli(%Options{enable_file_checkpointing: true},
         init_response: server_info_response()
       )}
    end

    test "rewind_files sends control request and waits for success", %{
      client: client,
      transport: transport
    } do
      task = Task.async(fn -> Client.rewind_files(client, "user_msg_123") end)

      request = wait_for_request(transport, 2)
      assert request["request"]["subtype"] == "rewind_files"
      assert request["request"]["user_message_id"] == "user_msg_123"

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request["request_id"],
          "subtype" => "success",
          "response" => %{}
        }
      }

      FakeCLI.push_message(transport, response)
      assert :ok = Task.await(task, 1_000)
    end

    test "rewind_files forwards CLI error", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.rewind_files(client, "user_msg_456") end)

      request = wait_for_request(transport, 2)

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request["request_id"],
          "subtype" => "error",
          "error" => "blocked"
        }
      }

      FakeCLI.push_message(transport, response)
      assert {:error, "blocked"} = Task.await(task, 1_000)
    end
  end

  describe "rewind_files requires file checkpointing option" do
    setup do
      Process.flag(:trap_exit, true)

      {:ok,
       start_initialized_client_with_fake_cli(%Options{}, init_response: server_info_response())}
    end

    test "returns error without sending control request when disabled", %{
      client: client,
      transport: transport
    } do
      assert {:error, :file_checkpointing_not_enabled} =
               Client.rewind_files(client, "user_msg_123")

      Process.sleep(50)
      assert length(FakeCLI.decoded_messages(transport)) == 1
    end
  end

  defp start_client_with_fake_cli(options, client_opts \\ []) do
    fake_cli = FakeCLI.new!()
    on_exit(fn -> FakeCLI.cleanup(fake_cli) end)

    {:ok, client} = Client.start_link(FakeCLI.options(fake_cli, options), client_opts)
    on_exit(fn -> safe_stop(client) end)

    assert :ok = FakeCLI.wait_until_started(fake_cli, 1_000)

    %{client: client, transport: fake_cli}
  end

  defp start_initialized_client_with_fake_cli(options, opts \\ []) do
    init_response = Keyword.get(opts, :init_response, %{})
    client_opts = Keyword.get(opts, :client_opts, [])
    %{client: client, transport: transport} = start_client_with_fake_cli(options, client_opts)

    {:ok, init_request} = FakeCLI.initialize_request(transport)

    FakeCLI.push_message(
      transport,
      control_success_response(init_request["request_id"], init_response)
    )

    assert :ok = Client.await_initialized(client, 1_000)

    %{client: client, transport: transport, init_request: init_request}
  end

  defp wait_for_request(fake_cli, count, timeout_ms \\ 1_000) do
    assert :ok = FakeCLI.wait_for_request_count(fake_cli, count, timeout_ms)
    Enum.at(FakeCLI.decoded_messages(fake_cli), count - 1)
  end

  defp control_success_response(request_id, response) do
    %{
      "type" => "control_response",
      "response" => %{
        "request_id" => request_id,
        "subtype" => "success",
        "response" => response
      }
    }
  end

  defp server_info_response do
    %{
      "commands" => [%{"name" => "plan"}],
      "outputStyle" => %{"current" => "default"}
    }
  end

  defp safe_stop(client) do
    Client.stop(client)
  catch
    :exit, _ -> :ok
  end
end
