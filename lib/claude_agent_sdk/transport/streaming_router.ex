defmodule ClaudeAgentSDK.Transport.StreamingRouter do
  @moduledoc """
  Selects streaming transport based on required features.

  ## Decision Algorithm

  1. Check explicit override (`preferred_transport`)
  2. Detect control protocol requirements
  3. Default to CLI-only for performance

  ## Examples

      # Simple streaming → CLI-only
      iex> select_transport(%Options{})
      :streaming_session

      # With hooks → Control client
      iex> select_transport(%Options{hooks: %{pre_tool_use: [...]}})
      :control_client

      # Override
      iex> select_transport(%Options{preferred_transport: :cli})
      :streaming_session
  """

  alias ClaudeAgentSDK.Options

  @type transport_choice :: :streaming_session | :control_client

  @doc """
  Selects transport implementation.

  Returns `:streaming_session` (CLI-only) or `:control_client` (full features).

  ## Performance

  This is a pure function with no I/O. Typical execution: <0.1ms.
  """
  @spec select_transport(Options.t()) :: transport_choice()
  def select_transport(%Options{} = opts) do
    case explicit_override(opts) do
      nil -> automatic_selection(opts)
      choice -> choice
    end
  end

  @doc """
  Checks if options require control protocol.

  Useful for debugging transport selection.
  """
  @spec requires_control_protocol?(Options.t()) :: boolean()
  def requires_control_protocol?(opts) do
    automatic_selection(opts) == :control_client
  end

  @doc """
  Human-readable explanation of transport choice.

  ## Examples

      iex> StreamingRouter.explain(%Options{hooks: %{...}})
      \"\"\"
      Transport: control_client
      Reason: hooks detected
      Features: [:hooks]
      Override: none
      \"\"\"
  """
  @spec explain(Options.t()) :: String.t()
  def explain(%Options{} = opts) do
    choice = select_transport(opts)
    override = explicit_override(opts)
    features = detect_features(opts)
    reason = selection_reason(opts)

    """
    Transport: #{choice}
    Reason: #{reason}
    Features: #{inspect(features)}
    Override: #{inspect(override)}
    """
  end

  ## Private Implementation

  # Explicit user override
  defp explicit_override(%Options{preferred_transport: :cli}),
    do: :streaming_session

  defp explicit_override(%Options{preferred_transport: :control}),
    do: :control_client

  defp explicit_override(_), do: nil

  # Automatic selection based on features
  defp automatic_selection(opts) do
    if has_control_features?(opts) do
      :control_client
    else
      :streaming_session
    end
  end

  # Feature detection
  defp has_control_features?(opts) do
    has_hooks?(opts) or
      has_sdk_mcp_servers?(opts) or
      has_permission_callback?(opts) or
      has_active_agents?(opts) or
      has_special_permission_mode?(opts)
  end

  # Individual feature detectors

  defp has_hooks?(%Options{hooks: hooks})
       when is_map(hooks) and map_size(hooks) > 0 do
    # Empty map doesn't count
    Enum.any?(hooks, fn {_event, matchers} ->
      is_list(matchers) and matchers != []
    end)
  end

  defp has_hooks?(_), do: false

  defp has_sdk_mcp_servers?(%Options{mcp_servers: servers})
       when is_map(servers) do
    # Only SDK servers require control; external servers use CLI flags
    Enum.any?(servers, fn
      {_name, %{type: :sdk}} -> true
      _ -> false
    end)
  end

  defp has_sdk_mcp_servers?(_), do: false

  defp has_permission_callback?(%Options{can_use_tool: callback})
       when is_function(callback),
       do: true

  defp has_permission_callback?(_), do: false

  defp has_active_agents?(%Options{agents: agents, agent: active})
       when is_map(agents) and map_size(agents) > 0 and not is_nil(active),
       do: true

  defp has_active_agents?(%Options{agents: agents})
       when is_map(agents) and map_size(agents) > 0,
       do: true

  # Agents configured even if none active yet
  defp has_active_agents?(_), do: false

  defp has_special_permission_mode?(%Options{permission_mode: mode})
       when mode in [:accept_edits, :bypass_permissions, :plan, :delegate, :dont_ask],
       do: true

  defp has_special_permission_mode?(_), do: false

  # Introspection helpers

  defp detect_features(opts) do
    []
    |> add_if(has_hooks?(opts), :hooks)
    |> add_if(has_sdk_mcp_servers?(opts), :sdk_mcp)
    |> add_if(has_permission_callback?(opts), :permission_callback)
    |> add_if(has_active_agents?(opts), :agents)
    |> add_if(has_special_permission_mode?(opts), :special_permission_mode)
  end

  defp add_if(list, true, feature), do: [feature | list]
  defp add_if(list, false, _), do: list

  defp selection_reason(opts) do
    cond do
      explicit_override(opts) == :streaming_session ->
        "explicit override to CLI"

      explicit_override(opts) == :control_client ->
        "explicit override to control"

      has_hooks?(opts) ->
        "hooks detected"

      has_sdk_mcp_servers?(opts) ->
        "SDK MCP servers detected"

      has_permission_callback?(opts) ->
        "permission callback detected"

      has_active_agents?(opts) ->
        "runtime agents detected"

      has_special_permission_mode?(opts) ->
        "special permission mode detected"

      true ->
        "default (no control features)"
    end
  end
end
