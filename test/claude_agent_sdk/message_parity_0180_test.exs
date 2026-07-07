defmodule ClaudeAgentSDK.MessageParity0180Test do
  @moduledoc """
  Parity coverage for the 0.18.0 message-surface additions (Python v0.2.111 /
  TypeScript v0.3.202): api_error_status, refusal stop_details, task_updated,
  hook events, deferred tool use, model_fallback, tool_use_meta, surfaced
  metadata, and rate-limit fields.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Message

  defp parse!(map) do
    {:ok, msg} = map |> Jason.encode!() |> Message.from_json()
    msg
  end

  describe "result message parity" do
    test "surfaces api_error_status" do
      msg =
        parse!(%{
          "type" => "result",
          "subtype" => "success",
          "is_error" => true,
          "session_id" => "s1",
          "api_error_status" => 529
        })

      assert msg.data.api_error_status == 529
    end

    test "api_error_status is absent when not provided" do
      msg = parse!(%{"type" => "result", "subtype" => "success", "session_id" => "s1"})
      refute Map.has_key?(msg.data, :api_error_status)
    end

    test "surfaces deferred_tool_use" do
      msg =
        parse!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s1",
          "deferred_tool_use" => %{"id" => "tu_1", "name" => "Bash", "input" => %{"cmd" => "ls"}}
        })

      assert msg.data.deferred_tool_use == %{
               id: "tu_1",
               name: "Bash",
               input: %{"cmd" => "ls"}
             }
    end

    test "surfaces origin" do
      msg =
        parse!(%{
          "type" => "result",
          "subtype" => "success",
          "session_id" => "s1",
          "origin" => "task-notification"
        })

      assert msg.data.origin == "task-notification"
    end
  end

  describe "assistant message parity" do
    test "surfaces refusal stop_reason and stop_details" do
      msg =
        parse!(%{
          "type" => "assistant",
          "session_id" => "s1",
          "message" => %{
            "content" => [],
            "stop_reason" => "refusal",
            "stop_details" => %{
              "type" => "refusal",
              "category" => "cyber",
              "explanation" => "declined"
            }
          }
        })

      assert msg.data.stop_reason == "refusal"

      assert msg.data.stop_details == %{
               "type" => "refusal",
               "category" => "cyber",
               "explanation" => "declined"
             }
    end

    test "surfaces tool_use_meta and parent_agent_id" do
      msg =
        parse!(%{
          "type" => "assistant",
          "session_id" => "s1",
          "parent_agent_id" => "agent_7",
          "message" => %{
            "content" => [],
            "tool_use_meta" => %{"display_name" => "Run Bash", "icon_url" => "https://x/i.png"}
          }
        })

      assert msg.data.parent_agent_id == "agent_7"
      assert msg.data.tool_use_meta["icon_url"] == "https://x/i.png"
    end

    test "does not raise when content is a plain string" do
      msg =
        parse!(%{
          "type" => "assistant",
          "session_id" => "s1",
          "message" => %{"content" => "hello world"}
        })

      assert [%{type: :text, text: "hello world"}] = Message.content_blocks(msg)
    end

    test "model_not_found is a recognized assistant error" do
      msg =
        parse!(%{
          "type" => "assistant",
          "session_id" => "s1",
          "message" => %{"content" => [], "error" => "model_not_found"}
        })

      assert msg.data.error == :model_not_found
    end
  end

  describe "task_updated lifecycle" do
    test "parses task_updated frame" do
      msg =
        parse!(%{
          "type" => "system",
          "subtype" => "task_updated",
          "task_id" => "t1",
          "session_id" => "s1",
          "uuid" => "u1",
          "patch" => %{"status" => "killed"}
        })

      assert msg.subtype == :task_updated
      assert msg.data.task_id == "t1"
      assert msg.data.status == "killed"
      assert msg.data.patch == %{"status" => "killed"}
    end

    test "terminal_task_status?/1 covers both vocabularies" do
      assert Message.terminal_task_status?("completed")
      assert Message.terminal_task_status?("failed")
      assert Message.terminal_task_status?("stopped")
      assert Message.terminal_task_status?("killed")
      assert Message.terminal_task_status?(:killed)
      refute Message.terminal_task_status?("running")
      refute Message.terminal_task_status?(nil)
    end
  end

  describe "hook event message" do
    test "parses hook_started and hook_response frames" do
      for subtype <- ["hook_started", "hook_response"] do
        msg =
          parse!(%{
            "type" => "system",
            "subtype" => subtype,
            "session_id" => "s1",
            "uuid" => "u1",
            "hook_event_name" => "PreToolUse"
          })

        assert msg.subtype == String.to_atom(subtype)
        assert msg.data.hook_event_name == "PreToolUse"
      end
    end
  end

  describe "system/model_fallback message" do
    test "parses model_fallback frame with trigger" do
      msg =
        parse!(%{
          "type" => "system",
          "subtype" => "model_fallback",
          "session_id" => "s1",
          "trigger" => "overloaded",
          "from_model" => "claude-opus-4-8",
          "to_model" => "claude-sonnet-5"
        })

      assert msg.subtype == :model_fallback
      assert msg.data.trigger == "overloaded"
      assert msg.data.from_model == "claude-opus-4-8"
      assert msg.data.to_model == "claude-sonnet-5"
    end
  end

  describe "rate limit info parity" do
    test "surfaces new SDKRateLimitInfo fields" do
      msg =
        parse!(%{
          "type" => "rate_limit_event",
          "uuid" => "u1",
          "session_id" => "s1",
          "rate_limit_info" => %{
            "status" => "allowed_warning",
            "rateLimitType" => "seven_day_overage_included",
            "errorCode" => "credits_required",
            "canUserPurchaseCredits" => true,
            "hasChargeableSavedPaymentMethod" => false,
            "modelScoped" => [%{"model" => "claude-opus-4-8", "utilization" => 0.5}]
          }
        })

      info = msg.data.rate_limit_info
      assert info.rate_limit_type == "seven_day_overage_included"
      assert info.error_code == "credits_required"
      assert info.can_user_purchase_credits == true
      assert info.has_chargeable_saved_payment_method == false
      assert info.model_scoped == [%{"model" => "claude-opus-4-8", "utilization" => 0.5}]
    end
  end
end
