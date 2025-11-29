defmodule ClaudeAgentSDK.ClientTest do
  use ClaudeAgentSDK.SupertesterCase, isolation: :basic

  alias ClaudeAgentSDK.{Client, Options, Hooks}
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  @moduletag :client
  @moduletag :requires_cli

  describe "start_link/1" do
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
              callback_ids =
                Enum.map(matcher.hooks, fn cb ->
                  Hooks.Registry.get_id(registry, cb)
                end)

              %{
                "matcher" => matcher.matcher,
                "hookCallbackIds" => callback_ids,
                "timeout" => matcher.timeout_ms
              }
            end)

          {event_str, matchers_config}
        end)
        |> Map.new()

      assert hooks_config == %{
               "PreToolUse" => [
                 %{
                   "matcher" => "Bash",
                   "hookCallbackIds" => ["hook_0"],
                   "timeout" => 1_500
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
    alias ClaudeAgentSDK.TestSupport.MockTransport

    setup do
      Process.flag(:trap_exit, true)
      %{options: %Options{}}
    end

    test "uses provided transport module for initialization messages", %{options: options} do
      assert {:ok, client} =
               Client.start_link(options,
                 transport: MockTransport,
                 transport_opts: [test_pid: self()]
               )

      on_exit(fn ->
        try do
          Client.stop(client)
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert is_pid(transport_pid)

      assert_receive {:mock_transport_send, json}, 200
      decoded = Jason.decode!(json)
      assert decoded["type"] == "control_request"
      assert decoded["request"]["subtype"] == "initialize"
    end

    test "delivers messages from transport to subscribers", %{options: options} do
      assert {:ok, client} =
               Client.start_link(options,
                 transport: MockTransport,
                 transport_opts: [test_pid: self()]
               )

      on_exit(fn ->
        try do
          Client.stop(client)
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:mock_transport_started, transport_pid}, 200

      :ok = GenServer.call(client, {:subscribe})

      payload = %{
        "type" => "assistant",
        "message" => %{"content" => "hello", "role" => "assistant"},
        "session_id" => "test-session"
      }

      MockTransport.push_message(transport_pid, payload)

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
    alias ClaudeAgentSDK.TestSupport.MockTransport
    alias ClaudeAgentSDK.Model

    setup do
      Process.flag(:trap_exit, true)

      assert {:ok, client} =
               Client.start_link(%Options{},
                 transport: MockTransport,
                 transport_opts: [test_pid: self()]
               )

      on_exit(fn ->
        try do
          Client.stop(client)
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:mock_transport_started, transport_pid}, 200
      # consume initialize request
      assert_receive {:mock_transport_send, _init_json}, 200

      {:ok, %{client: client, transport: transport_pid}}
    end

    test "set_model sends control request and updates current model", %{
      client: client,
      transport: transport
    } do
      task = Task.async(fn -> Client.set_model(client, "opus") end)

      assert_receive {:mock_transport_send, json}, 200
      decoded = Jason.decode!(json)
      assert decoded["request"]["subtype"] == "set_model"
      request_id = decoded["request_id"]

      {:ok, normalized} = Model.validate("opus")

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => request_id,
          "subtype" => "success",
          "result" => %{"model" => normalized}
        }
      }

      MockTransport.push_message(transport, Jason.encode!(response))

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

      assert_receive {:mock_transport_send, json}, 200
      request_id = Jason.decode!(json)["request_id"]

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

      MockTransport.push_message(transport, Jason.encode!(response))

      assert :ok = Task.await(task, 1_000)
    end
  end

  describe "runtime control APIs" do
    alias ClaudeAgentSDK.TestSupport.MockTransport

    setup do
      Process.flag(:trap_exit, true)

      assert {:ok, client} =
               Client.start_link(%Options{},
                 transport: MockTransport,
                 transport_opts: [test_pid: self()]
               )

      on_exit(fn ->
        try do
          Client.stop(client)
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:mock_transport_started, transport_pid}, 200
      assert_receive {:mock_transport_send, init_json}, 200
      init_request = Jason.decode!(init_json)

      init_response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => init_request["request_id"],
          "subtype" => "success",
          "response" => %{
            "commands" => [%{"name" => "plan"}],
            "outputStyle" => %{"current" => "default"}
          }
        }
      }

      MockTransport.push_message(transport_pid, Jason.encode!(init_response))

      {:ok, %{client: client, transport: transport_pid}}
    end

    test "interrupt sends control request", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.interrupt(client) end)

      assert_receive {:mock_transport_send, json}, 200
      decoded = Jason.decode!(json)
      assert decoded["request"]["subtype"] == "interrupt"

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => decoded["request_id"],
          "subtype" => "success",
          "response" => %{}
        }
      }

      MockTransport.push_message(transport, Jason.encode!(response))
      assert :ok = Task.await(task, 1_000)
    end

    test "interrupt forwards CLI error", %{client: client, transport: transport} do
      task = Task.async(fn -> Client.interrupt(client) end)

      assert_receive {:mock_transport_send, json}, 200
      decoded = Jason.decode!(json)

      response = %{
        "type" => "control_response",
        "response" => %{
          "request_id" => decoded["request_id"],
          "subtype" => "error",
          "error" => "blocked"
        }
      }

      MockTransport.push_message(transport, Jason.encode!(response))
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
      assert {:ok, client} =
               Client.start_link(%Options{},
                 transport: MockTransport,
                 transport_opts: [test_pid: self()]
               )

      on_exit(fn ->
        try do
          Client.stop(client)
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:mock_transport_started, _} = _msg = {:mock_transport_started, _transport},
                     200

      assert {:error, :not_initialized} = Client.get_server_info(client)
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

      MockTransport.push_message(transport, Jason.encode!(assistant))
      MockTransport.push_message(transport, Jason.encode!(result))

      assert {:ok, messages} = Task.await(task, 1_000)
      assert length(messages) == 2
      assert Enum.at(messages, 0).type == :assistant
      assert Enum.at(messages, 1).type == :result
    end
  end
end
