defmodule ClaudeAgentSDK.Hooks.Matcher do
  @moduledoc """
  Hook matcher configuration.

  Defines which hooks should run for which tool patterns. Matchers support:

  - **Exact matching**: `"Bash"` matches only the Bash tool
  - **Regex patterns**: `"Write|Edit"` matches Write or Edit tools
  - **Wildcard**: `"*"` or `nil` matches all tools
  - **Multiple hooks**: Each matcher can have multiple callback functions

  ## Examples

      # Match specific tool
      Matcher.new("Bash", [&MyModule.check_bash/3])

      # Match multiple tools with regex
      Matcher.new("Write|Edit", [&check_file_edit/3])

      # Match all tools
      Matcher.new("*", [&log_all_tools/3])
      Matcher.new(nil, [&log_all_tools/3])

      # Multiple hooks for same pattern
      Matcher.new("Bash", [&security_check/3, &audit_log/3])
  """

  alias ClaudeAgentSDK.Hooks

  @typedoc """
  Hook matcher struct.

  Fields:
  - `matcher` - Tool name pattern (nil, "*", "ToolName", or regex like "Tool1|Tool2")
  - `hooks` - List of callback functions to invoke when pattern matches
  """
  @type t :: %__MODULE__{
          matcher: String.t() | nil,
          hooks: [Hooks.hook_callback()]
        }

  @enforce_keys [:hooks]
  defstruct [:matcher, :hooks]

  @doc """
  Creates a new hook matcher.

  ## Parameters

  - `matcher` - Tool name pattern. Can be:
    - `nil` - Matches all tools
    - `"*"` - Matches all tools
    - `"ToolName"` - Matches specific tool exactly
    - `"Tool1|Tool2"` - Regex pattern matching multiple tools
  - `hooks` - List of callback functions (each with signature `(input, tool_use_id, context) -> output`)

  ## Examples

      # Match Bash tool only
      Matcher.new("Bash", [&check_bash/3])

      # Match Write or Edit tools
      Matcher.new("Write|Edit", [&check_file_edit/3])

      # Match all tools
      Matcher.new(nil, [&log_all_tools/3])

      # Multiple hooks for same pattern
      Matcher.new("Bash", [&security_check/3, &audit_log/3])
  """
  @spec new(String.t() | nil, [Hooks.hook_callback()]) :: t()
  def new(matcher, hooks) when is_list(hooks) do
    %__MODULE__{
      matcher: matcher,
      hooks: hooks
    }
  end

  @doc """
  Converts matcher to CLI format for initialization.

  The callback_id_fn function is called for each hook to get its unique ID
  from the registry.

  ## Parameters

  - `matcher` - The matcher struct
  - `callback_id_fn` - Function that takes a callback and returns its ID string

  ## Returns

  Map with CLI-compatible format:
  - `"matcher"` - Tool pattern string or nil
  - `"hookCallbackIds"` - List of callback ID strings

  ## Examples

      matcher = Matcher.new("Bash", [&check_bash/3])
      id_fn = fn callback -> Registry.get_id(registry, callback) end

      Matcher.to_cli_format(matcher, id_fn)
      # => %{"matcher" => "Bash", "hookCallbackIds" => ["hook_0"]}
  """
  @spec to_cli_format(t(), (Hooks.hook_callback() -> String.t())) :: map()
  def to_cli_format(%__MODULE__{} = matcher, callback_id_fn)
      when is_function(callback_id_fn, 1) do
    callback_ids = Enum.map(matcher.hooks, callback_id_fn)

    %{
      "matcher" => matcher.matcher,
      "hookCallbackIds" => callback_ids
    }
  end
end
