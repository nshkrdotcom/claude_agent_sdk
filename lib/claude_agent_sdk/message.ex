defmodule ClaudeAgentSDK.Message do
  @moduledoc """
  Represents a message from Claude Code CLI.

  Messages are the core data structure returned by the Claude Code SDK. They represent
  different types of communication during a conversation with Claude, including system
  initialization, user inputs, assistant responses, and final results.

  This SDK is CLI-faithful: when the Claude CLI emits distinct message frames, the Elixir
  SDK prefers surfacing them directly even if the current Python SDK filters some unknown
  message types for forward compatibility.

  ## Message Types

  - `:system` - Session initialization messages with metadata
  - `:user` - User input messages (echoed back from CLI)
  - `:assistant` - Claude's response messages containing the actual AI output
  - `:rate_limit_event` - Rate limit state changes emitted by the CLI
  - `:result` - Final result messages with cost, duration, and completion status

  Assistant messages may optionally include an `error` code when the CLI surfaces
  an issue (e.g., `:rate_limit` or `:authentication_failed`).

  ## Result Subtypes

  - `:success` - Successful completion
  - `:error_max_turns` - Terminated due to max turns limit
  - `:error_during_execution` - Error occurred during execution

  ## System Subtypes

  - `:init` - Initial system message with session setup

  ## Examples

      # Assistant message
      %ClaudeAgentSDK.Message{
        type: :assistant,
        subtype: nil,
        data: %{
          message: %{"content" => "Hello! How can I help?"},
          session_id: "session-123"
        }
      }

      # Assistant message with error metadata
      %ClaudeAgentSDK.Message{
        type: :assistant,
        subtype: nil,
        data: %{
          message: %{"content" => "Please try again later."},
          session_id: "session-123",
          error: :rate_limit
        }
      }

      # Result message
      %ClaudeAgentSDK.Message{
        type: :result,
        subtype: :success,
        data: %{
          total_cost_usd: 0.001,
          duration_ms: 1500,
          num_turns: 2,
          session_id: "session-123"
        }
      }

  """

  alias ClaudeAgentSDK.AssistantError
  alias ClaudeAgentSDK.Schema.Message, as: MessageSchema

  defstruct [:type, :subtype, :data, :raw]

  @type message_type ::
          :assistant
          | :user
          | :result
          | :system
          | :stream_event
          | :rate_limit_event
          | :unknown
          | String.t()
  @type result_subtype :: :success | :error_max_turns | :error_during_execution | String.t()
  @type system_subtype ::
          :init
          | :task_started
          | :task_progress
          | :task_notification
          | :task_updated
          | :background_tasks_changed
          | :model_fallback
          | :hook_started
          | :hook_response
          | :mirror_error
          | String.t()
  @type assistant_error :: AssistantError.t()
  @type rate_limit_info :: %{
          required(:status) => String.t(),
          optional(:resets_at) => integer() | nil,
          optional(:rate_limit_type) => String.t() | nil,
          optional(:utilization) => float() | integer() | nil,
          optional(:is_using_overage) => boolean() | nil,
          optional(:overage_status) => String.t() | nil,
          optional(:overage_resets_at) => integer() | nil,
          optional(:overage_disabled_reason) => String.t() | nil,
          optional(:error_code) => String.t() | nil,
          optional(:can_user_purchase_credits) => boolean() | nil,
          optional(:has_chargeable_saved_payment_method) => boolean() | nil,
          optional(:model_scoped) => [map()] | nil,
          optional(:raw) => map()
        }
  @type rate_limit_data :: %{
          required(:rate_limit_info) => rate_limit_info(),
          required(:uuid) => String.t(),
          required(:session_id) => String.t()
        }
  @type assistant_data :: %{
          required(:message) => map(),
          required(:session_id) => String.t() | nil,
          optional(:parent_tool_use_id) => String.t() | nil,
          optional(:error) => assistant_error() | nil
        }

  @type t :: %__MODULE__{
          type: message_type(),
          subtype: result_subtype() | system_subtype() | nil,
          data: assistant_data() | map(),
          raw: map()
        }

  # Terminal task statuses span both the `task_notification` vocabulary
  # (completed/failed/stopped) and the `task_updated` vocabulary
  # (completed/failed/killed). Clearing active-task tracking on any of these
  # avoids hangs when a task ends via `task_updated` without a notification.
  @terminal_task_statuses ~w(completed failed stopped killed)

  @doc """
  Returns `true` when a task status is terminal (from either the
  `task_notification` or `task_updated` vocabulary).
  """
  @spec terminal_task_status?(String.t() | atom() | nil) :: boolean()
  def terminal_task_status?(status) when is_atom(status) and not is_nil(status),
    do: terminal_task_status?(Atom.to_string(status))

  def terminal_task_status?(status) when is_binary(status),
    do: status in @terminal_task_statuses

  def terminal_task_status?(_status), do: false

  # Dead-turn terminal reasons per the CLI 2.1.207 classifier: the turn died
  # under the hood (its command lifecycle reports cancelled, not completed).
  # Aborts (aborted_streaming/aborted_tools), max_turns, background_requested,
  # completed, and unknown/absent reasons are NOT dead turns. Values stay
  # strings — no atoms are minted from wire data.
  @dead_terminal_reasons ~w(
    blocking_limit rapid_refill_breaker prompt_too_long image_error
    model_error api_error malformed_tool_use_exhausted budget_exhausted
    structured_output_retry_exhausted tool_deferred_unavailable
    turn_setup_failed
  )

  @doc """
  Returns `true` when a result's `terminal_reason` indicates a dead turn —
  one that failed or was cancelled under the hood rather than completing
  cleanly (CLI 2.1.204+).

  Accepts a result `Message`, a `terminal_reason` string, or `nil`. Unknown
  and absent reasons are not dead turns.
  """
  @spec dead_turn?(t() | String.t() | nil) :: boolean()
  def dead_turn?(%__MODULE__{data: %{terminal_reason: reason}}), do: dead_turn?(reason)
  def dead_turn?(%__MODULE__{}), do: false
  def dead_turn?(reason) when is_binary(reason), do: reason in @dead_terminal_reasons
  def dead_turn?(_reason), do: false

  @doc """
  Returns the live (non-terminal) background tasks from a
  `background_tasks_changed` system frame.

  The frame is level-based — `tasks` is the full current set — and tasks
  without a `status` are live, so this only drops tasks whose status is
  terminal. Returns `[]` for any other message.
  """
  @spec live_background_tasks(t()) :: [map()]
  def live_background_tasks(%__MODULE__{
        subtype: :background_tasks_changed,
        data: %{tasks: tasks}
      })
      when is_list(tasks) do
    Enum.reject(tasks, fn task ->
      terminal_task_status?(task[:status] || task["status"])
    end)
  end

  def live_background_tasks(%__MODULE__{}), do: []

  @doc false
  def __safe_type__(type), do: safe_type(type)

  @doc false
  def __safe_subtype__(type, subtype), do: safe_subtype(type, subtype)

  @doc """
  Parses a JSON message from Claude Code into a Message struct.

  ## Parameters

  - `json_string` - Raw JSON string from Claude CLI

  ## Returns

  - `{:ok, message}` - Successfully parsed message
  - `{:error, reason}` - Parsing failed

  ## Examples

      iex> ClaudeAgentSDK.Message.from_json(~s({"type":"assistant","message":{"content":"Hello"}}))
      {:ok, %ClaudeAgentSDK.Message{type: :assistant, ...}}

  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json_string) when is_binary(json_string) do
    case ClaudeAgentSDK.JSON.decode(json_string) do
      {:ok, raw} when is_map(raw) ->
        {:ok, parse_message(raw)}

      {:ok, raw} ->
        {:error, {:parse_error, "expected JSON object, got: #{inspect(raw)}"}}

      {:error, reason} ->
        {:error, {:parse_error, format_parse_error(reason)}}
    end
  rescue
    error ->
      {:error, {:parse_error, Exception.message(error)}}
  end

  @doc """
  Returns parsed content blocks for `:user` and `:assistant` messages.

  This is an ergonomic alternative to the Python SDK's typed content-block objects.
  """
  @spec content_blocks(t()) :: [map()]
  def content_blocks(%__MODULE__{type: type, data: %{message: %{"content" => content}}})
      when type in [:user, :assistant] do
    cond do
      is_list(content) ->
        Enum.map(content, &parse_content_block/1)

      is_binary(content) ->
        [%{type: :text, text: content}]

      true ->
        []
    end
  end

  def content_blocks(_message), do: []

  @doc false
  @spec error_result(String.t(), keyword()) :: t()
  def error_result(error_message, opts \\ []) when is_binary(error_message) and is_list(opts) do
    session_id = Keyword.get(opts, :session_id, "error")
    error_struct = Keyword.get(opts, :error_struct)
    error_details = Keyword.get(opts, :error_details)

    data =
      %{
        error: error_message,
        session_id: session_id,
        is_error: true
      }
      |> maybe_put_error_struct(error_struct)
      |> maybe_put_error_details(error_details, error_struct)

    %__MODULE__{
      type: :result,
      subtype: :error_during_execution,
      data: data,
      raw: %{}
    }
  end

  defp maybe_put_error_struct(data, nil), do: data
  defp maybe_put_error_struct(data, error_struct), do: Map.put(data, :error_struct, error_struct)

  defp maybe_put_error_details(data, error_details, _error_struct) when is_map(error_details) do
    Map.put(data, :error_details, error_details)
  end

  defp maybe_put_error_details(data, nil, %ClaudeAgentSDK.Errors.ProcessError{} = error_struct) do
    Map.put(data, :error_details, %{
      kind: :process_error,
      exit_code: error_struct.exit_code,
      stderr: error_struct.stderr
    })
  end

  defp maybe_put_error_details(data, nil, _error_struct), do: data

  defp maybe_put(data, _key, nil), do: data
  defp maybe_put(data, key, value), do: Map.put(data, key, value)

  defp parse_message(raw) do
    case MessageSchema.parse(raw) do
      {:ok, parsed} ->
        type = safe_type(parsed["type"])

        message = %__MODULE__{
          type: type,
          raw: raw
        }

        parse_by_type(message, type, parsed)

      {:error, {:invalid_message_frame, details}} ->
        case parse_message_with_raw_frame(raw) do
          {:ok, message} -> message
          :error -> raise ArgumentError, details.message
        end
    end
  end

  defp parse_message_with_raw_frame(%{"type" => type} = raw) when is_binary(type) do
    case String.trim(type) do
      "" ->
        :error

      trimmed_type ->
        type = safe_type(trimmed_type)
        parsed = %{raw | "type" => trimmed_type}

        message = %__MODULE__{
          type: type,
          raw: raw
        }

        {:ok, parse_by_type(message, type, parsed)}
    end
  end

  defp parse_message_with_raw_frame(_raw), do: :error

  defp parse_by_type(message, :assistant, raw) do
    %{message | data: build_assistant_data(raw)}
  end

  defp parse_by_type(message, :user, raw) do
    data =
      %{
        message: raw["message"],
        session_id: raw["session_id"],
        parent_tool_use_id: raw["parent_tool_use_id"],
        tool_use_result: raw["tool_use_result"]
      }
      |> maybe_put_uuid(raw)

    %{message | data: data}
  end

  defp parse_by_type(message, :result, raw) do
    subtype = safe_result_subtype(raw)

    data =
      case subtype do
        :success -> build_result_data(:success, raw)
        :error_max_turns -> build_result_data(:error_max_turns, raw)
        :error_during_execution -> build_result_data(:error_during_execution, raw)
        # Unknown result subtypes (e.g. error_max_budget_usd) keep the raw
        # frame but still surface the shared parity fields additively.
        _ -> put_result_parity_fields(raw, raw)
      end

    %{message | subtype: subtype, data: data}
  end

  defp parse_by_type(message, :system, raw) do
    subtype = safe_subtype(:system, raw["subtype"])

    %{message | subtype: subtype, data: build_system_subtype_data(subtype, raw)}
  end

  defp parse_by_type(message, :stream_event, raw) do
    data = %{
      uuid: Map.get(raw, "uuid"),
      session_id: Map.get(raw, "session_id"),
      event: Map.get(raw, "event", %{}),
      parent_tool_use_id: raw["parent_tool_use_id"]
    }

    %{message | data: data}
  end

  defp parse_by_type(message, :rate_limit_event, raw) do
    %{message | data: build_rate_limit_event_data(raw)}
  end

  defp parse_by_type(message, _unknown_type, raw) do
    %{message | data: raw}
  end

  defp build_system_subtype_data(:init, raw), do: build_system_data(:init, raw)
  defp build_system_subtype_data(:task_started, raw), do: build_task_started_data(raw)
  defp build_system_subtype_data(:task_progress, raw), do: build_task_progress_data(raw)
  defp build_system_subtype_data(:task_notification, raw), do: build_task_notification_data(raw)
  defp build_system_subtype_data(:task_updated, raw), do: build_task_updated_data(raw)

  defp build_system_subtype_data(:background_tasks_changed, raw),
    do: build_background_tasks_changed_data(raw)

  defp build_system_subtype_data(:model_fallback, raw), do: build_model_fallback_data(raw)
  defp build_system_subtype_data(:hook_started, raw), do: build_hook_event_data(raw)
  defp build_system_subtype_data(:hook_response, raw), do: build_hook_event_data(raw)
  defp build_system_subtype_data(:mirror_error, raw), do: build_mirror_error_data(raw)
  defp build_system_subtype_data(_subtype, raw), do: raw

  defp safe_type(type) when is_binary(type) do
    case type do
      "assistant" -> :assistant
      "user" -> :user
      "result" -> :result
      "system" -> :system
      "stream_event" -> :stream_event
      "rate_limit_event" -> :rate_limit_event
      other -> other
    end
  end

  defp safe_type(_), do: :unknown

  defp format_parse_error(:invalid_json), do: "invalid JSON"

  defp safe_subtype(:result, subtype) when is_binary(subtype) do
    case subtype do
      "success" -> :success
      "error_max_turns" -> :error_max_turns
      "error_during_execution" -> :error_during_execution
      other -> other
    end
  end

  @system_subtypes %{
    "init" => :init,
    "task_started" => :task_started,
    "task_progress" => :task_progress,
    "task_notification" => :task_notification,
    "task_updated" => :task_updated,
    "background_tasks_changed" => :background_tasks_changed,
    "model_fallback" => :model_fallback,
    "hook_started" => :hook_started,
    "hook_response" => :hook_response,
    "mirror_error" => :mirror_error
  }

  defp safe_subtype(:system, subtype) when is_binary(subtype) do
    Map.get(@system_subtypes, subtype, subtype)
  end

  defp safe_subtype(_type, subtype) when is_binary(subtype), do: subtype
  defp safe_subtype(_type, _subtype), do: nil

  defp safe_result_subtype(%{"subtype" => subtype, "is_error" => true})
       when subtype in ["success", :success] do
    :error_during_execution
  end

  defp safe_result_subtype(%{} = raw), do: safe_subtype(:result, raw["subtype"])

  defp parse_content_block(%{"type" => "text", "text" => text}) when is_binary(text),
    do: %{type: :text, text: text}

  defp parse_content_block(%{"type" => "thinking"} = block) do
    %{
      type: :thinking,
      thinking: block["thinking"],
      signature: block["signature"]
    }
  end

  defp parse_content_block(%{"type" => "tool_use"} = block) do
    %{
      type: :tool_use,
      id: block["id"],
      name: block["name"],
      input: block["input"] || %{}
    }
  end

  defp parse_content_block(%{"type" => "tool_result"} = block) do
    %{
      type: :tool_result,
      tool_use_id: block["tool_use_id"],
      content: block["content"],
      is_error: block["is_error"]
    }
  end

  defp parse_content_block(%{"type" => "server_tool_use"} = block) do
    %{
      type: :server_tool_use,
      id: block["id"],
      name: block["name"],
      input: block["input"] || %{}
    }
  end

  defp parse_content_block(%{"type" => "advisor_tool_result"} = block) do
    %{
      type: :advisor_tool_result,
      tool_use_id: block["tool_use_id"],
      content: block["content"]
    }
  end

  defp parse_content_block(block) when is_map(block), do: %{type: :unknown, raw: block}
  defp parse_content_block(other), do: %{type: :unknown, raw: other}

  # Extract uuid from user messages for file checkpointing support
  defp maybe_put_uuid(data, %{"uuid" => uuid}) when is_binary(uuid) and uuid != "" do
    Map.put(data, :uuid, uuid)
  end

  defp maybe_put_uuid(data, _raw), do: data

  defp build_assistant_data(raw) do
    error_value = get_in(raw, ["message", "error"]) || raw["error"]

    %{
      message: raw["message"],
      session_id: raw["session_id"],
      parent_tool_use_id: raw["parent_tool_use_id"]
    }
    |> maybe_put(:uuid, raw["uuid"])
    |> maybe_put(:message_id, get_in(raw, ["message", "id"]))
    |> maybe_put(:stop_reason, get_in(raw, ["message", "stop_reason"]))
    |> maybe_put(:stop_details, get_in(raw, ["message", "stop_details"]) || raw["stop_details"])
    |> maybe_put(:usage, get_in(raw, ["message", "usage"]))
    |> maybe_put(
      :tool_use_meta,
      get_in(raw, ["message", "tool_use_meta"]) || raw["tool_use_meta"]
    )
    |> maybe_put(:parent_agent_id, raw["parent_agent_id"])
    |> maybe_put_assistant_error(error_value)
  end

  defp maybe_put_assistant_error(data, error_value) do
    case AssistantError.cast(error_value) do
      nil -> data
      parsed_error -> Map.put(data, :error, parsed_error)
    end
  end

  defp build_result_data(:success, raw) do
    %{
      result: raw["result"],
      session_id: raw["session_id"],
      structured_output: raw["structured_output"],
      usage: raw["usage"],
      total_cost_usd: raw["total_cost_usd"],
      duration_ms: raw["duration_ms"],
      duration_api_ms: raw["duration_api_ms"],
      num_turns: raw["num_turns"],
      is_error: raw["is_error"],
      stop_reason: raw["stop_reason"]
    }
    |> put_result_parity_fields(raw)
  end

  defp build_result_data(error_type, raw)
       when error_type in [:error_max_turns, :error_during_execution] do
    error_message = get_error_message(error_type, raw["error"] || raw["result"])

    %{
      session_id: raw["session_id"],
      structured_output: raw["structured_output"],
      usage: raw["usage"],
      total_cost_usd: raw["total_cost_usd"] || 0.0,
      duration_ms: raw["duration_ms"] || 0,
      duration_api_ms: raw["duration_api_ms"] || 0,
      num_turns: raw["num_turns"] || 0,
      is_error: raw["is_error"] || true,
      error: error_message,
      stop_reason: raw["stop_reason"]
    }
    |> put_result_parity_fields(raw)
  end

  defp put_result_parity_fields(data, raw) do
    data
    |> maybe_put(:uuid, raw["uuid"])
    |> maybe_put(:model_usage, raw["modelUsage"])
    |> maybe_put(:permission_denials, raw["permission_denials"])
    |> maybe_put(:errors, raw["errors"])
    |> maybe_put(:api_error_status, raw["api_error_status"])
    |> maybe_put(:deferred_tool_use, parse_deferred_tool_use(raw["deferred_tool_use"]))
    |> maybe_put(:origin, raw["origin"])
    |> maybe_put(:terminal_reason, raw["terminal_reason"])
  end

  defp parse_deferred_tool_use(%{} = deferred) do
    %{
      id: deferred["id"],
      name: deferred["name"],
      input: deferred["input"] || %{}
    }
  end

  defp parse_deferred_tool_use(_), do: nil

  defp get_error_message(:error_max_turns, nil) do
    "The task exceeded the maximum number of turns allowed. Consider increasing max_turns option for complex tasks."
  end

  defp get_error_message(:error_max_turns, "") do
    "The task exceeded the maximum number of turns allowed. Consider increasing max_turns option for complex tasks."
  end

  defp get_error_message(:error_during_execution, nil) do
    "An error occurred during task execution."
  end

  defp get_error_message(:error_during_execution, "") do
    "An error occurred during task execution."
  end

  defp get_error_message(_error_type, error_message) when is_binary(error_message) do
    error_message
  end

  defp get_error_message(_error_type, _) do
    "An unknown error occurred."
  end

  defp build_system_data(:init, raw) do
    Map.merge(raw, %{
      api_key_source: raw["apiKeySource"],
      cwd: raw["cwd"],
      session_id: raw["session_id"],
      tools: raw["tools"] || [],
      mcp_servers: raw["mcp_servers"] || [],
      model: raw["model"],
      permission_mode: raw["permissionMode"]
    })
  end

  defp build_mirror_error_data(raw) do
    Map.merge(raw, %{
      subtype: :mirror_error,
      session_id: raw["session_id"],
      key: raw["key"],
      error: raw["error"]
    })
  end

  defp build_task_started_data(raw) do
    Map.merge(raw, %{
      task_id: raw["task_id"],
      description: raw["description"],
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      tool_use_id: raw["tool_use_id"],
      task_type: raw["task_type"],
      request_id: raw["request_id"],
      subagent_type: raw["subagent_type"],
      task_description: raw["task_description"]
    })
  end

  defp build_task_progress_data(raw) do
    Map.merge(raw, %{
      task_id: raw["task_id"],
      description: raw["description"],
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      tool_use_id: raw["tool_use_id"],
      usage: raw["usage"],
      last_tool_name: raw["last_tool_name"],
      request_id: raw["request_id"],
      subagent_type: raw["subagent_type"],
      task_description: raw["task_description"]
    })
  end

  defp build_task_updated_data(raw) do
    patch = raw["patch"]

    Map.merge(raw, %{
      task_id: raw["task_id"],
      patch: patch,
      status: task_updated_status(patch, raw["status"]),
      session_id: raw["session_id"],
      uuid: raw["uuid"]
    })
  end

  defp task_updated_status(%{} = patch, fallback), do: patch["status"] || fallback
  defp task_updated_status(_patch, fallback), do: fallback

  # Level-based frame: `tasks` is the full live background-task set on every
  # membership change (an empty list means the set drained). Per-task keys
  # observed on CLI 2.1.207: task_id, task_type, description; status is
  # optional (absent means the task is live).
  defp build_background_tasks_changed_data(raw) do
    tasks = raw["tasks"] || raw["background_tasks"] || []

    Map.merge(raw, %{
      tasks: Enum.map(tasks, &build_background_task/1),
      session_id: raw["session_id"],
      uuid: raw["uuid"]
    })
  end

  defp build_background_task(%{} = task) do
    Map.merge(task, %{
      task_id: task["task_id"],
      task_type: task["task_type"],
      status: task["status"],
      description: task["description"] || task["task_description"],
      tool_use_id: task["tool_use_id"],
      subagent_type: task["subagent_type"]
    })
  end

  defp build_background_task(other), do: other

  defp build_model_fallback_data(raw) do
    Map.merge(raw, %{
      trigger: raw["trigger"],
      from_model: raw["from_model"] || raw["fromModel"],
      to_model: raw["to_model"] || raw["toModel"],
      session_id: raw["session_id"],
      uuid: raw["uuid"]
    })
  end

  defp build_hook_event_data(raw) do
    Map.merge(raw, %{
      hook_event_name: raw["hook_event_name"] || raw["hook_event"] || raw["hook_name"],
      session_id: raw["session_id"],
      uuid: raw["uuid"]
    })
  end

  defp build_task_notification_data(raw) do
    Map.merge(raw, %{
      task_id: raw["task_id"],
      status: raw["status"],
      output_file: raw["output_file"],
      summary: raw["summary"],
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      tool_use_id: raw["tool_use_id"],
      usage: raw["usage"]
    })
  end

  defp build_rate_limit_event_data(raw) do
    info = Map.fetch!(raw, "rate_limit_info")

    %{
      rate_limit_info: %{
        status: Map.fetch!(info, "status"),
        resets_at: info["resetsAt"],
        rate_limit_type: info["rateLimitType"],
        utilization: info["utilization"],
        is_using_overage: info["isUsingOverage"],
        overage_status: info["overageStatus"],
        overage_resets_at: info["overageResetsAt"],
        overage_disabled_reason: info["overageDisabledReason"],
        error_code: info["errorCode"],
        can_user_purchase_credits: info["canUserPurchaseCredits"],
        has_chargeable_saved_payment_method: info["hasChargeableSavedPaymentMethod"],
        model_scoped: info["modelScoped"],
        raw: info
      },
      uuid: Map.fetch!(raw, "uuid"),
      session_id: Map.fetch!(raw, "session_id")
    }
  end

  @doc """
  Checks if the message is a final result message.

  Final messages indicate the end of a conversation or query.

  ## Parameters

  - `message` - The message to check

  ## Returns

  `true` if the message is a final result, `false` otherwise.

  ## Examples

      iex> ClaudeAgentSDK.Message.final?(%ClaudeAgentSDK.Message{type: :result})
      true

      iex> ClaudeAgentSDK.Message.final?(%ClaudeAgentSDK.Message{type: :assistant})
      false

  """
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{type: :result}), do: true
  def final?(_), do: false

  @doc """
  Checks if the message indicates an error.

  Returns `true` for result messages with error subtypes
  (`:error_max_turns` or `:error_during_execution`).
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{type: :result, subtype: subtype})
      when subtype in [:error_max_turns, :error_during_execution],
      do: true

  def error?(%__MODULE__{type: :result, data: %{is_error: true}}), do: true

  def error?(_), do: false

  @doc """
  Gets the session ID from a message.

  Returns `nil` if the message does not contain a session ID.
  """
  @spec session_id(t()) :: String.t() | nil
  def session_id(%__MODULE__{data: %{session_id: id}}), do: id
  def session_id(_), do: nil

  @doc """
  Returns the checkpoint UUID from a user message, or nil.

  Used with file checkpointing to identify rewind targets.
  """
  @spec user_uuid(t()) :: String.t() | nil
  def user_uuid(%__MODULE__{type: :user, data: %{uuid: uuid}})
      when is_binary(uuid) and uuid != "",
      do: uuid

  def user_uuid(%__MODULE__{type: :user, raw: %{"uuid" => uuid}})
      when is_binary(uuid) and uuid != "",
      do: uuid

  def user_uuid(_), do: nil
end
