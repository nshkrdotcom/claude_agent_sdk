defmodule ClaudeAgentSDK.Options do
  @moduledoc """
  Configuration options for Claude Code SDK requests.

  This struct defines all available options that can be passed to Claude Code CLI.
  All fields are optional and will be omitted from the CLI command if not provided.

  ## Fields

  - `max_turns` - Maximum number of conversation turns (integer)
  - `system_prompt` - Custom system prompt to use (string)
  - `append_system_prompt` - Additional system prompt to append (string)
  - `output_format` - Output format (`:text`, `:json`, `:stream_json`, or structured JSON schema config)
  - `tools` - Base tools set selection (`--tools`) (Python v0.1.12+)
  - `allowed_tools` - List of allowed tool names (list of strings)
  - `disallowed_tools` - List of disallowed tool names (list of strings)
  - `mcp_servers` - Map of MCP server configurations or JSON/path string (v0.5.0+)
  - `mcp_config` - Path to MCP configuration file (string, backward compat)
  - `betas` - SDK beta feature flags (`--betas`) (Python v0.1.12+)
  - `permission_prompt_tool` - Tool for permission prompts (string)
  - `permission_mode` - Permission handling mode (see `t:permission_mode/0`)
  - `cwd` - Working directory for the CLI (string)
  - `verbose` - Enable verbose output (boolean)
  - `executable` - Custom executable to run (string)
  - `executable_args` - Arguments for custom executable (list of strings)
  - `path_to_claude_code_executable` - Path to Claude Code CLI (string)
  - `abort_ref` - Reference for aborting requests (reference)
  - `hooks` - Hook configurations (see `t:ClaudeAgentSDK.Hooks.hook_config/0`)
  - `timeout_ms` - Command execution timeout in milliseconds (integer, default: 4_500_000)
  - `sandbox` - Sandbox settings merged into `--settings` JSON when present (Python v0.1.12+)
  - `enable_file_checkpointing` - Enables file checkpointing + `rewind_files` (Python v0.1.15+)
  - `include_partial_messages` - Enable character-level streaming (boolean) (v0.8.0+)
  - `stream_buffer_limit` - Max inbound entries buffered before first subscriber (integer, default: 1000)
  - `preferred_transport` - Override automatic transport selection (`:auto | :cli | :control`) (v0.8.0+)

  ## Streaming + Tools (v0.8.0)

  The SDK automatically selects the appropriate transport:
  - **CLI-only**: Fast streaming without control features (no hooks, MCP, or permissions)
  - **Control client**: Full features with streaming (hooks + partial messages)

  Override with `preferred_transport`:
  - `:auto` - Automatic selection (default)
  - `:cli` - Force CLI-only mode (ignores control features)
  - `:control` - Force control client (even without features)

  ## Examples

      # Basic configuration
      %ClaudeAgentSDK.Options{
        max_turns: 5,
        output_format: :stream_json,
        verbose: true
      }

      # Advanced configuration
      %ClaudeAgentSDK.Options{
        system_prompt: "You are a helpful coding assistant",
        allowed_tools: ["editor", "bash"],
        permission_mode: :accept_edits,
        cwd: "/path/to/project"
      }

      # Streaming with tools (v0.8.0)
      %ClaudeAgentSDK.Options{
        include_partial_messages: true,
        hooks: %{pre_tool_use: [...]},
        mcp_servers: %{"math" => sdk_server}
      }
      # → Automatically selects control client with streaming enabled

  """

  # This struct intentionally has many fields as it mirrors the Claude Code CLI options.
  # The struct is created once per request and is short-lived, so memory overhead is minimal.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :max_turns,
    :system_prompt,
    :append_system_prompt,
    :output_format,
    :tools,
    :allowed_tools,
    :disallowed_tools,
    :max_budget_usd,
    :continue_conversation,
    :resume,
    :settings,
    :setting_sources,
    :sandbox,
    # MCP Configuration (v0.5.0+)
    # Programmatic MCP server definitions (SDK and external)
    :mcp_servers,
    # File path to MCP config (backward compat with earlier versions)
    :mcp_config,
    :permission_prompt_tool,
    :permission_mode,
    :cwd,
    :verbose,
    :executable,
    :executable_args,
    :path_to_claude_code_executable,
    :abort_ref,
    # New fields for v0.1.0
    # Model selection ("opus", "sonnet", "haiku", or full name)
    :model,
    # Fallback model when primary is busy
    :fallback_model,
    # SDK beta feature flags (Python v0.1.12+)
    # Custom agent definitions
    :agents,
    # Active agent (atom key from agents map)
    :agent,
    # Explicit session ID (UUID)
    :session_id,
    # Quick wins (v0.2.0)
    # Create new session ID when resuming
    :fork_session,
    # Additional directories for tool access
    :add_dir,
    # Only use MCP servers from --mcp-config
    :strict_mcp_config,
    # Hooks (v0.3.0)
    # Hook callbacks for lifecycle events
    :hooks,
    # Permission System (v0.4.0)
    # Permission callback function
    :can_use_tool,
    # Timeout for command execution in milliseconds (default: 4_500_000 = 75 minutes)
    :timeout_ms,
    # File checkpointing (Python v0.1.15+)
    :enable_file_checkpointing,
    # Streaming + Tools (v0.8.0)
    # Enable character-level streaming with --include-partial-messages
    :include_partial_messages,
    # Buffer inbound events/messages before a subscriber attaches
    :stream_buffer_limit,
    # Override automatic transport selection
    :preferred_transport,
    :user,
    :max_thinking_tokens,
    :max_buffer_size,
    betas: [],
    plugins: [],
    add_dirs: [],
    extra_args: %{},
    env: %{},
    stderr: nil
  ]

  @type structured_output_format ::
          {:json_schema, map()}
          | %{
              required(:type) => :json_schema | String.t(),
              required(:schema) => map(),
              optional(:output_format) => :json | :stream_json | String.t()
            }

  @type output_format :: :text | :json | :stream_json | structured_output_format()
  @type permission_mode ::
          :default | :accept_edits | :bypass_permissions | :plan | :delegate | :dont_ask
  @type model_name :: String.t()
  @type agent_name :: atom()
  @type agent_definition :: ClaudeAgentSDK.Agent.t()
  @type transport_preference :: :auto | :cli | :control

  @typedoc """
  Tools preset configuration.
  """
  @type tools_preset :: %{
          required(:type) => :preset | String.t(),
          required(:preset) => :claude_code | String.t()
        }

  @typedoc """
  Tools option - controls the base set of available tools.

  Supported forms:
  - List of tool names: `["Read", "Edit"]`
  - Empty list: `[]` (disables all built-in tools)
  - Preset map: `%{type: :preset, preset: :claude_code}` (maps to `"default"`)
  """
  @type tools_option :: [String.t()] | tools_preset() | map() | nil

  @typedoc """
  SDK beta feature flag.
  """
  @type sdk_beta :: String.t()

  @typedoc """
  SDK MCP server configuration (in-process)
  """
  @type sdk_mcp_server :: %{
          type: :sdk,
          name: String.t(),
          version: String.t(),
          registry_pid: pid()
        }

  @typedoc """
  External MCP server configuration (subprocess via stdio)
  """
  @type stdio_mcp_server :: %{
          type: :stdio,
          command: String.t(),
          args: [String.t()]
        }

  @typedoc """
  SSE MCP server configuration (Server-Sent Events).
  Headers is optional (defaults to empty map if not provided).
  """
  @type sse_mcp_server :: %{
          :type => :sse,
          :url => String.t(),
          optional(:headers) => %{String.t() => String.t()}
        }

  @typedoc """
  HTTP MCP server configuration (HTTP transport).
  Headers is optional (defaults to empty map if not provided).
  """
  @type http_mcp_server :: %{
          :type => :http,
          :url => String.t(),
          optional(:headers) => %{String.t() => String.t()}
        }

  @typedoc """
  External MCP server (stdio, sse, or http)
  """
  @type external_mcp_server :: stdio_mcp_server() | sse_mcp_server() | http_mcp_server()

  @typedoc """
  MCP server (either SDK or external)
  """
  @type mcp_server :: sdk_mcp_server() | external_mcp_server()

  @typedoc """
  Plugin configuration supported by the SDK (currently local directories only).
  """
  @type plugin_config :: %{
          required(:type) => :local | String.t(),
          required(:path) => String.t()
        }

  @type t :: %__MODULE__{
          max_turns: integer() | nil,
          system_prompt: String.t() | map() | nil,
          append_system_prompt: String.t() | nil,
          output_format: output_format() | nil,
          tools: tools_option(),
          allowed_tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,
          max_budget_usd: number() | nil,
          continue_conversation: boolean() | nil,
          resume: String.t() | nil,
          settings: String.t() | nil,
          setting_sources: [String.t() | atom()] | nil,
          sandbox: map() | nil,
          plugins: [plugin_config()],
          mcp_servers: %{String.t() => mcp_server()} | String.t() | nil,
          mcp_config: String.t() | nil,
          permission_prompt_tool: String.t() | nil,
          permission_mode: permission_mode() | nil,
          cwd: String.t() | nil,
          verbose: boolean() | nil,
          executable: String.t() | nil,
          executable_args: [String.t()] | nil,
          path_to_claude_code_executable: String.t() | nil,
          abort_ref: reference() | nil,
          model: model_name() | nil,
          fallback_model: model_name() | nil,
          betas: [sdk_beta()] | nil,
          agents: %{agent_name() => agent_definition()} | nil,
          agent: agent_name() | nil,
          session_id: String.t() | nil,
          fork_session: boolean() | nil,
          add_dir: [String.t()] | nil,
          add_dirs: [String.t()] | nil,
          strict_mcp_config: boolean() | nil,
          hooks: ClaudeAgentSDK.Hooks.hook_config() | nil,
          can_use_tool: ClaudeAgentSDK.Permission.callback() | nil,
          timeout_ms: integer() | nil,
          enable_file_checkpointing: boolean() | nil,
          include_partial_messages: boolean() | nil,
          stream_buffer_limit: non_neg_integer() | nil,
          preferred_transport: transport_preference() | nil,
          max_buffer_size: pos_integer() | nil,
          extra_args: %{optional(String.t()) => String.t() | boolean() | nil},
          env: %{optional(String.t()) => String.t()},
          stderr: (String.t() -> any()) | nil,
          user: String.t() | nil,
          max_thinking_tokens: pos_integer() | nil
        }

  @doc """
  Creates a new Options struct with the given attributes.

  ## Parameters

  - `attrs` - Keyword list of attributes to set (keyword list)

  ## Returns

  A new `t:ClaudeAgentSDK.Options.t/0` struct with the specified attributes.

  ## Examples

      ClaudeAgentSDK.Options.new(
        max_turns: 5,
        output_format: :json,
        verbose: true
      )

      # Empty options (all defaults)
      ClaudeAgentSDK.Options.new()

  """
  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts the options to command line arguments for the Claude CLI.

  ## Parameters

  - `options` - The options struct to convert

  ## Returns

  A list of strings representing CLI arguments.

  ## Examples

      options = %ClaudeAgentSDK.Options{max_turns: 5, verbose: true}
      ClaudeAgentSDK.Options.to_args(options)
      # => ["--max-turns", "5", "--verbose"]

  """
  @spec to_args(t()) :: [String.t()]
  def to_args(%__MODULE__{} = options) do
    []
    |> add_output_format_args(options)
    |> add_max_turns_args(options)
    |> add_max_budget_args(options)
    |> add_system_prompt_args(options)
    |> add_append_system_prompt_args(options)
    |> add_tools_args(options)
    |> add_allowed_tools_args(options)
    |> add_disallowed_tools_args(options)
    |> add_continue_args(options)
    |> add_resume_args(options)
    |> add_settings_args(options)
    |> add_setting_sources_args(options)
    |> add_mcp_args(options)
    |> add_permission_prompt_tool_args(options)
    |> add_permission_mode_args(options)
    |> add_verbose_args(options)
    |> add_model_args(options)
    |> add_fallback_model_args(options)
    |> add_betas_args(options)
    |> add_agent_args(options)
    |> add_session_id_args(options)
    |> add_fork_session_args(options)
    |> add_dir_args(options)
    |> add_plugins_args(options)
    |> add_strict_mcp_args(options)
    |> add_partial_messages_args(options)
    |> add_max_thinking_tokens_args(options)
    |> add_extra_args(options)
  end

  @doc false
  @spec to_stream_json_args(t()) :: [String.t()]
  def to_stream_json_args(%__MODULE__{} = options) do
    options
    |> to_args()
    |> strip_flag_with_value("--output-format")
    |> Enum.reject(&(&1 == "--verbose"))
  end

  defp add_output_format_args(args, %{output_format: nil}), do: args

  defp add_output_format_args(args, %{output_format: format}) do
    case normalize_output_format(format) do
      {:standard, normalized_format} ->
        args
        |> Kernel.++(["--output-format", to_cli_format(normalized_format)])
        |> Kernel.++(verbose_if_stream(normalized_format))

      {:json_schema, schema, base_format} ->
        args
        |> Kernel.++(["--output-format", to_cli_format(base_format)])
        |> Kernel.++(["--json-schema", Jason.encode!(schema)])
        |> Kernel.++(verbose_if_stream(base_format))
    end
  end

  defp normalize_output_format(format) when format in [:text, :json, :stream_json] do
    {:standard, format}
  end

  defp normalize_output_format("text"), do: {:standard, :text}
  defp normalize_output_format("json"), do: {:standard, :json}
  defp normalize_output_format("stream-json"), do: {:standard, :stream_json}
  defp normalize_output_format("stream_json"), do: {:standard, :stream_json}

  defp normalize_output_format({:json_schema, schema}) when is_map(schema) do
    {:json_schema, schema, :json}
  end

  defp normalize_output_format({:json_schema, _schema}) do
    raise ArgumentError, "structured output_format schema must be a map"
  end

  defp normalize_output_format(%{} = config) do
    normalize_structured_output_config(config)
  end

  defp normalize_output_format(other) when is_binary(other) do
    raise ArgumentError, "Unsupported output_format: #{inspect(other)}"
  end

  defp normalize_output_format(other) do
    raise ArgumentError, "Unsupported output_format: #{inspect(other)}"
  end

  defp normalize_structured_output_config(config) do
    type = Map.get(config, :type) || Map.get(config, "type")
    schema = Map.get(config, :schema) || Map.get(config, "schema")
    base_format = Map.get(config, :output_format) || Map.get(config, "output_format") || :json

    cond do
      type in [:json_schema, "json_schema"] and is_map(schema) ->
        {:json_schema, schema, normalize_base_output_format(base_format)}

      type in [:json_schema, "json_schema"] ->
        raise ArgumentError, "structured output_format schema must be a map"

      true ->
        raise ArgumentError, "Unsupported structured output_format config: #{inspect(config)}"
    end
  end

  defp normalize_base_output_format(:json), do: :json
  defp normalize_base_output_format("json"), do: :json
  defp normalize_base_output_format(:stream_json), do: :stream_json
  defp normalize_base_output_format("stream-json"), do: :stream_json
  defp normalize_base_output_format("stream_json"), do: :stream_json

  defp normalize_base_output_format(other) do
    raise ArgumentError,
          "Unsupported base output_format for structured outputs: #{inspect(other)}"
  end

  defp to_cli_format(:stream_json), do: "stream-json"

  defp to_cli_format(other) when is_atom(other) or is_binary(other) do
    to_string(other)
  end

  defp verbose_if_stream(:stream_json), do: ["--verbose"]
  defp verbose_if_stream(_), do: []

  defp strip_flag_with_value(args, flag) do
    args
    |> Enum.reduce({[], false}, fn
      ^flag, {acc, _skip_next} ->
        {acc, true}

      _value, {acc, true} ->
        {acc, false}

      value, {acc, false} ->
        {[value | acc], false}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp add_max_turns_args(args, %{max_turns: nil}), do: args

  defp add_max_turns_args(args, %{max_turns: turns}),
    do: args ++ ["--max-turns", to_string(turns)]

  defp add_max_budget_args(args, %{max_budget_usd: nil}), do: args

  defp add_max_budget_args(args, %{max_budget_usd: budget}) when is_number(budget) do
    args ++ ["--max-budget-usd", to_string(budget)]
  end

  # Python parity: always emit an explicit system prompt flag when unset.
  # When unset, this forces "no system prompt" rather than relying on CLI defaults.
  defp add_system_prompt_args(args, %{system_prompt: nil}), do: args ++ ["--system-prompt", ""]

  defp add_system_prompt_args(args, %{system_prompt: prompt}) when is_binary(prompt),
    do: args ++ ["--system-prompt", prompt]

  # Python parity: support SystemPromptPreset objects (type=preset, preset=claude_code, optional append).
  # A preset with no append emits no system-prompt flags (uses CLI default prompt).
  defp add_system_prompt_args(args, %{system_prompt: %{} = preset}) do
    case normalize_system_prompt_preset(preset) do
      {:preset, _preset, _append} ->
        args

      :invalid ->
        raise ArgumentError,
              "system_prompt preset must be %{type: :preset, preset: :claude_code, append: ...} (or string-keyed equivalent)"
    end
  end

  defp add_append_system_prompt_args(args, %{
         append_system_prompt: nil,
         system_prompt: %{} = preset
       }) do
    case normalize_system_prompt_preset(preset) do
      {:preset, _preset, append} when is_binary(append) and append != "" ->
        args ++ ["--append-system-prompt", append]

      {:preset, _preset, _append} ->
        args

      :invalid ->
        args
    end
  end

  defp add_append_system_prompt_args(args, %{append_system_prompt: nil}), do: args

  defp add_append_system_prompt_args(args, %{append_system_prompt: prompt}),
    do: args ++ ["--append-system-prompt", prompt]

  defp normalize_system_prompt_preset(%{"type" => "preset"} = preset),
    do: normalize_system_prompt_preset(string_keyed_to_atom_keyed(preset))

  defp normalize_system_prompt_preset(%{type: "preset"} = preset),
    do: normalize_system_prompt_preset(%{preset | type: :preset})

  defp normalize_system_prompt_preset(%{type: :preset, preset: preset} = map) do
    preset_atom =
      cond do
        preset == :claude_code -> :claude_code
        preset == "claude_code" -> :claude_code
        true -> nil
      end

    if preset_atom != :claude_code do
      :invalid
    else
      append =
        case Map.fetch(map, :append) do
          {:ok, value} when is_binary(value) -> value
          _ -> nil
        end

      {:preset, :claude_code, append}
    end
  end

  defp normalize_system_prompt_preset(_), do: :invalid

  defp string_keyed_to_atom_keyed(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      case k do
        "type" -> Map.put(acc, :type, v)
        "preset" -> Map.put(acc, :preset, v)
        "append" -> Map.put(acc, :append, v)
        _other -> acc
      end
    end)
  end

  defp add_tools_args(args, %{tools: nil}), do: args

  defp add_tools_args(args, %{tools: tools}) when is_list(tools) do
    if tools == [] do
      args ++ ["--tools", ""]
    else
      args ++ ["--tools", Enum.join(tools, ",")]
    end
  end

  defp add_tools_args(args, %{tools: tools}) when is_map(tools) do
    # Python treats any preset object as the Claude Code default tools set.
    _ = tools
    args ++ ["--tools", "default"]
  end

  defp add_allowed_tools_args(args, %{allowed_tools: nil}), do: args

  defp add_allowed_tools_args(args, %{allowed_tools: tools}) when tools == [], do: args

  defp add_allowed_tools_args(args, %{allowed_tools: tools}),
    do: args ++ ["--allowedTools", Enum.join(tools, ",")]

  defp add_disallowed_tools_args(args, %{disallowed_tools: nil}), do: args

  defp add_disallowed_tools_args(args, %{disallowed_tools: tools}) when tools == [],
    do: args

  defp add_disallowed_tools_args(args, %{disallowed_tools: tools}),
    do: args ++ ["--disallowedTools", Enum.join(tools, ",")]

  defp add_continue_args(args, %{continue_conversation: true}), do: args ++ ["--continue"]
  defp add_continue_args(args, _), do: args

  defp add_resume_args(args, %{resume: nil}), do: args
  defp add_resume_args(args, %{resume: resume}), do: args ++ ["--resume", resume]

  defp add_settings_args(args, options) do
    case build_settings_value(options) do
      nil -> args
      value -> args ++ ["--settings", value]
    end
  end

  defp build_settings_value(%{settings: nil, sandbox: nil}), do: nil

  defp build_settings_value(%{settings: settings, sandbox: nil}) when is_binary(settings) do
    settings
  end

  defp build_settings_value(%{settings: settings, sandbox: sandbox}) when not is_nil(sandbox) do
    settings_obj = parse_existing_settings(settings)

    settings_obj
    |> Map.put("sandbox", deep_stringify_keys(sandbox))
    |> deep_stringify_keys()
    |> Jason.encode!()
  end

  defp parse_existing_settings(nil), do: %{}

  defp parse_existing_settings(settings) when is_binary(settings) do
    trimmed = String.trim(settings)

    cond do
      trimmed == "" ->
        %{}

      String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") ->
        case Jason.decode(trimmed) do
          {:ok, obj} when is_map(obj) -> obj
          _ -> read_settings_file(trimmed)
        end

      true ->
        read_settings_file(trimmed)
    end
  end

  defp read_settings_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, obj} when is_map(obj) -> obj
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  defp deep_stringify_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      string_key =
        cond do
          is_binary(key) -> key
          is_atom(key) -> Atom.to_string(key)
          true -> to_string(key)
        end

      Map.put(acc, string_key, deep_stringify_keys(val))
    end)
  end

  defp deep_stringify_keys(value) when is_list(value) do
    Enum.map(value, &deep_stringify_keys/1)
  end

  defp deep_stringify_keys(value) when is_atom(value) and value not in [nil, true, false] do
    Atom.to_string(value)
  end

  defp deep_stringify_keys(value), do: value

  # Do not emit --setting-sources by default. Passing an empty value can disable
  # CLI-side persisted context (including resume session lookup).
  defp add_setting_sources_args(args, %{setting_sources: nil}), do: args

  defp add_setting_sources_args(args, %{setting_sources: sources}) when is_list(sources) do
    value = Enum.map_join(sources, ",", &to_string/1)

    args ++ ["--setting-sources", value]
  end

  # MCP Configuration - handles both mcp_servers (v0.5.0+) and mcp_config (backward compat)
  # IMPORTANT: ALL servers (including SDK type) must be passed to the CLI so Claude knows
  # the tools exist. The control protocol handles execution, but the CLI needs the server
  # metadata to expose tools to Claude. This matches the Python SDK behavior.
  defp add_mcp_args(args, options) do
    cond do
      # Priority 1: mcp_servers (new programmatic API)
      is_map(options.mcp_servers) and map_size(options.mcp_servers) > 0 ->
        # Pass ALL servers to CLI (both SDK and external)
        # SDK servers get their registry_pid stripped, external servers pass through as-is
        # This matches Python SDK behavior in subprocess_cli.py lines 246-268
        servers_for_cli = prepare_servers_for_cli(options.mcp_servers)
        # Wrap in {"mcpServers": ...} format like Python SDK does
        json_config = Jason.encode!(%{"mcpServers" => servers_for_cli})
        args ++ ["--mcp-config", json_config]

      # mcp_servers JSON string or file path
      is_binary(options.mcp_servers) ->
        args ++ ["--mcp-config", options.mcp_servers]

      # Priority 2: mcp_config file path (backward compat)
      is_binary(options.mcp_config) ->
        args ++ ["--mcp-config", options.mcp_config]

      # No MCP configuration
      true ->
        args
    end
  end

  @doc """
  Prepares MCP server configurations for the Claude CLI.

  SDK servers: Strips the registry_pid field (CLI doesn't need it)
  External servers: Passed through as-is

  ## Parameters

  - `servers` - Map of server name to server configuration

  ## Returns

  Map ready to be JSON-encoded for --mcp-config argument
  """
  @spec prepare_servers_for_cli(%{String.t() => mcp_server()}) :: %{String.t() => map()}
  def prepare_servers_for_cli(servers) do
    for {name, config} <- servers, into: %{} do
      {name, prepare_server_for_cli(config)}
    end
  end

  defp prepare_server_for_cli(%{type: :sdk} = sdk_server) do
    # Strip registry_pid - CLI doesn't need internal PID
    %{
      "type" => "sdk",
      "name" => sdk_server.name,
      "version" => sdk_server.version || "1.0.0"
    }
  end

  defp prepare_server_for_cli(%{type: :sse, url: url} = server) do
    %{
      "type" => "sse",
      "url" => url,
      "headers" => server[:headers] || %{}
    }
  end

  defp prepare_server_for_cli(%{type: :http, url: url} = server) do
    %{
      "type" => "http",
      "url" => url,
      "headers" => server[:headers] || %{}
    }
  end

  defp prepare_server_for_cli(external_server) do
    # stdio and other external servers - convert to string keys for JSON
    stringify_keys(external_server)
  end

  # Helper to convert atom keys and values to strings for JSON serialization
  defp stringify_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      {to_string(k), stringify_value(v)}
    end
  end

  defp stringify_value(v) when is_atom(v) and not is_nil(v), do: Atom.to_string(v)
  defp stringify_value(v), do: v

  defp add_permission_prompt_tool_args(args, %{permission_prompt_tool: nil}), do: args

  defp add_permission_prompt_tool_args(args, %{permission_prompt_tool: tool}),
    do: args ++ ["--permission-prompt-tool", tool]

  defp add_permission_mode_args(args, %{permission_mode: nil}), do: args

  defp add_permission_mode_args(args, %{permission_mode: mode}) do
    # Convert permission mode atom to CLI string format
    mode_string =
      case mode do
        :accept_edits -> "acceptEdits"
        :bypass_permissions -> "bypassPermissions"
        :dont_ask -> "dontAsk"
        other -> to_string(other)
      end

    args ++ ["--permission-mode", mode_string]
  end

  defp add_verbose_args(args, %{verbose: true}), do: args ++ ["--verbose"]
  defp add_verbose_args(args, _), do: args

  defp add_model_args(args, %{model: nil}), do: args
  defp add_model_args(args, %{model: model}), do: args ++ ["--model", model]

  defp add_fallback_model_args(args, %{fallback_model: nil}), do: args

  defp add_fallback_model_args(args, %{fallback_model: model}),
    do: args ++ ["--fallback-model", model]

  @doc """
  Converts the agents map to CLI-compatible format for the initialize request.

  Transforms `%{atom_name => Agent.t()}` to `%{"string_name" => cli_map}`.

  ## Parameters

  - `agents` - Map of atom names to Agent structs

  ## Returns

  Map of string names to CLI-compatible maps, or nil if no agents.
  """
  @spec agents_for_initialize(%{agent_name() => agent_definition()} | nil) :: map() | nil
  def agents_for_initialize(nil), do: nil
  def agents_for_initialize(agents) when agents == %{}, do: nil

  def agents_for_initialize(agents) when is_map(agents) do
    agents
    |> Enum.map(fn {name, agent} ->
      {to_string(name), ClaudeAgentSDK.Agent.to_cli_map(agent)}
    end)
    |> Map.new()
  end

  defp add_agent_args(args, %{agent: nil}), do: args

  defp add_agent_args(args, %{agent: agent}) when is_atom(agent) do
    args ++ ["--agent", to_string(agent)]
  end

  defp add_session_id_args(args, %{session_id: nil}), do: args
  defp add_session_id_args(args, %{session_id: id}), do: args ++ ["--session-id", id]

  defp add_fork_session_args(args, %{fork_session: true}), do: args ++ ["--fork-session"]
  defp add_fork_session_args(args, _), do: args

  defp add_dir_args(args, %{add_dir: add_dir, add_dirs: add_dirs}) do
    directories =
      []
      |> append_directories(add_dir)
      |> append_directories(add_dirs)

    Enum.reduce(directories, args, fn dir, acc -> acc ++ ["--add-dir", dir] end)
  end

  defp add_dir_args(args, %{add_dir: add_dir}) do
    add_dir_args(args, %{add_dir: add_dir, add_dirs: nil})
  end

  defp append_directories(list, nil), do: list
  defp append_directories(list, dirs) when is_list(dirs), do: list ++ dirs

  defp append_directories(list, dir) when is_binary(dir), do: list ++ [dir]

  defp add_strict_mcp_args(args, %{strict_mcp_config: true}), do: args ++ ["--strict-mcp-config"]
  defp add_strict_mcp_args(args, _), do: args

  defp add_partial_messages_args(args, %{include_partial_messages: true}),
    do: args ++ ["--include-partial-messages"]

  defp add_partial_messages_args(args, _), do: args

  defp add_plugins_args(args, %{plugins: plugins}) when is_list(plugins) do
    Enum.reduce(plugins, args, fn plugin, acc ->
      case normalize_plugin(plugin) do
        {:ok, %{path: path}} ->
          acc ++ ["--plugin-dir", path]

        {:error, reason} ->
          raise ArgumentError, "Invalid plugin configuration: #{reason}"
      end
    end)
  end

  defp add_plugins_args(args, _), do: args

  defp add_max_thinking_tokens_args(args, %{max_thinking_tokens: nil}), do: args

  defp add_max_thinking_tokens_args(args, %{max_thinking_tokens: tokens}) do
    args ++ ["--max-thinking-tokens", to_string(tokens)]
  end

  defp add_betas_args(args, %{betas: betas}) when is_list(betas) and betas != [] do
    args ++ ["--betas", Enum.join(betas, ",")]
  end

  defp add_betas_args(args, _), do: args

  defp add_extra_args(args, %{extra_args: extra_args}) when is_map(extra_args) do
    extra_args
    |> Enum.sort_by(fn {flag, _} -> flag end)
    |> Enum.reduce(args, fn {flag, value}, acc ->
      cli_flag = "--" <> flag

      cond do
        is_nil(value) ->
          acc ++ [cli_flag]

        value == true ->
          acc ++ [cli_flag]

        value == false ->
          acc

        true ->
          acc ++ [cli_flag, to_string(value)]
      end
    end)
  end

  defp add_extra_args(args, _), do: args

  defp normalize_plugin(%{type: type, path: path}) do
    case normalize_plugin_type(type) do
      :local when is_binary(path) ->
        {:ok, %{path: path}}

      :local ->
        {:error, "plugin path must be a string"}

      _ ->
        {:error, "unsupported plugin type #{inspect(type)}"}
    end
  end

  defp normalize_plugin(other) when is_map(other) do
    required = Map.take(other, [:type, "type", :path, "path"])

    with {:ok, type} <- fetch_plugin_type(required),
         {:ok, path} <- fetch_plugin_path(required) do
      normalize_plugin(%{type: type, path: path})
    end
  end

  defp normalize_plugin(_), do: {:error, "plugin must be a map with :type and :path"}

  defp normalize_plugin_type(:local), do: :local
  defp normalize_plugin_type("local"), do: :local
  defp normalize_plugin_type(other), do: other

  defp fetch_plugin_type(%{type: type}), do: {:ok, type}
  defp fetch_plugin_type(%{"type" => type}), do: {:ok, type}
  defp fetch_plugin_type(_), do: {:error, "missing plugin type"}

  defp fetch_plugin_path(%{path: path}), do: {:ok, path}
  defp fetch_plugin_path(%{"path" => path}), do: {:ok, path}
  defp fetch_plugin_path(_), do: {:error, "missing plugin path"}

  @doc """
  Validates agent configuration in Options.

  Ensures that:
  - All agents in the agents map are valid Agent structs
  - If an active agent is specified, it exists in the agents map
  - Agents and agent fields have correct types

  ## Parameters

  - `options` - Options struct to validate

  ## Returns

  - `:ok` if validation succeeds
  - `{:error, reason}` if validation fails

  ## Examples

      options = Options.new(
        agents: %{test: Agent.new(description: "Test", prompt: "Test")},
        agent: :test
      )
      Options.validate_agents(options)
      #=> :ok

      invalid = Options.new(
        agents: %{test: Agent.new(description: "Test", prompt: "Test")},
        agent: :nonexistent
      )
      Options.validate_agents(invalid)
      #=> {:error, {:agent_not_found, :nonexistent}}
  """
  @spec validate_agents(t()) :: :ok | {:error, term()}
  def validate_agents(%__MODULE__{agents: nil, agent: nil}), do: :ok
  def validate_agents(%__MODULE__{agents: nil, agent: _}), do: {:error, :no_agents_configured}

  def validate_agents(%__MODULE__{agents: agents, agent: active_agent}) when is_map(agents) do
    # Validate all agents in the map
    with :ok <- validate_agents_map(agents) do
      validate_active_agent(agents, active_agent)
    end
  end

  def validate_agents(%__MODULE__{agents: agents}) when not is_map(agents) do
    {:error, :agents_must_be_map}
  end

  defp validate_agents_map(agents) when is_map(agents) do
    Enum.reduce_while(agents, :ok, fn {name, agent}, _acc ->
      case ClaudeAgentSDK.Agent.validate(agent) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:invalid_agent, name, reason}}}
      end
    end)
  end

  defp validate_active_agent(_agents, nil), do: :ok

  defp validate_active_agent(agents, active_agent) when is_atom(active_agent) do
    if Map.has_key?(agents, active_agent) do
      :ok
    else
      {:error, {:agent_not_found, active_agent}}
    end
  end

  defp validate_active_agent(_agents, _active_agent) do
    {:error, :agent_must_be_atom}
  end
end
