defmodule ClaudeAgentSDK.Permission.Update do
  @moduledoc """
  Permission update types for configuring permissions via the control protocol.

  These types match the TypeScript/Python SDK permission update structures and can
  be used to programmatically update tool permissions in sessions.

  ## Update Types

  - `:add_rules` - Add new permission rules
  - `:replace_rules` - Replace existing permission rules
  - `:remove_rules` - Remove specific permission rules
  - `:set_mode` - Change the permission mode
  - `:add_directories` - Add directories to allowed paths
  - `:remove_directories` - Remove directories from allowed paths

  ## Destinations

  Permission updates can target different storage locations:

  - `:user_settings` - User-level settings (persistent)
  - `:project_settings` - Project-level settings (persistent)
  - `:local_settings` - Local directory settings (persistent)
  - `:session` - Session-only settings (temporary)

  ## Examples

      # Add a rule to allow Bash commands in session
      update = Update.add_rules(
        rules: [RuleValue.new("Bash", "echo *")],
        behavior: :allow,
        destination: :session
      )

      # Set permission mode for the session
      update = Update.set_mode(:accept_edits, destination: :session)
  """

  alias ClaudeAgentSDK.Permission.RuleValue

  @typedoc """
  Destination for permission updates.
  """
  @type destination :: :user_settings | :project_settings | :local_settings | :session

  @typedoc """
  Permission behavior for rules.
  """
  @type behavior :: :allow | :deny | :ask

  @typedoc """
  Permission update type.
  """
  @type update_type ::
          :add_rules
          | :replace_rules
          | :remove_rules
          | :set_mode
          | :add_directories
          | :remove_directories

  @typedoc """
  Permission update struct.
  """
  @type t :: %__MODULE__{
          type: update_type(),
          rules: [RuleValue.t()] | nil,
          behavior: behavior() | nil,
          mode: ClaudeAgentSDK.Permission.permission_mode() | nil,
          directories: [String.t()] | nil,
          destination: destination() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :rules, :behavior, :mode, :directories, :destination]

  @doc """
  Creates a new permission update.

  ## Parameters

  - `type` - Update type (:add_rules, :replace_rules, :remove_rules, :set_mode, :add_directories, :remove_directories)
  - `opts` - Options for the update (rules, behavior, mode, directories, destination)

  ## Examples

      Update.new(:add_rules,
        rules: [RuleValue.new("Bash", "echo *")],
        behavior: :allow,
        destination: :session
      )
  """
  @spec new(update_type(), keyword()) :: t()
  def new(type, opts \\ []) do
    %__MODULE__{
      type: type,
      rules: Keyword.get(opts, :rules),
      behavior: Keyword.get(opts, :behavior),
      mode: Keyword.get(opts, :mode),
      directories: Keyword.get(opts, :directories),
      destination: Keyword.get(opts, :destination)
    }
  end

  @doc """
  Creates an add_rules update.
  """
  @spec add_rules(keyword()) :: t()
  def add_rules(opts \\ []), do: new(:add_rules, opts)

  @doc """
  Creates a replace_rules update.
  """
  @spec replace_rules(keyword()) :: t()
  def replace_rules(opts \\ []), do: new(:replace_rules, opts)

  @doc """
  Creates a remove_rules update.
  """
  @spec remove_rules(keyword()) :: t()
  def remove_rules(opts \\ []), do: new(:remove_rules, opts)

  @doc """
  Creates a set_mode update.
  """
  @spec set_mode(ClaudeAgentSDK.Permission.permission_mode(), keyword()) :: t()
  def set_mode(mode, opts \\ []) do
    new(:set_mode, Keyword.put(opts, :mode, mode))
  end

  @doc """
  Creates an add_directories update.
  """
  @spec add_directories([String.t()], keyword()) :: t()
  def add_directories(directories, opts \\ []) do
    new(:add_directories, Keyword.put(opts, :directories, directories))
  end

  @doc """
  Creates a remove_directories update.
  """
  @spec remove_directories([String.t()], keyword()) :: t()
  def remove_directories(directories, opts \\ []) do
    new(:remove_directories, Keyword.put(opts, :directories, directories))
  end

  @doc """
  Converts a permission update to a map for the control protocol.

  ## Examples

      iex> update = Update.add_rules(
      ...>   rules: [RuleValue.new("Bash", "echo *")],
      ...>   behavior: :allow,
      ...>   destination: :session
      ...> )
      iex> Update.to_map(update)
      %{
        "type" => "addRules",
        "rules" => [%{"toolName" => "Bash", "ruleContent" => "echo *"}],
        "behavior" => "allow",
        "destination" => "session"
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = update) do
    base = %{"type" => type_to_string(update.type)}

    base
    |> maybe_add_destination(update)
    |> maybe_add_rules(update)
    |> maybe_add_behavior(update)
    |> maybe_add_mode(update)
    |> maybe_add_directories(update)
  end

  defp type_to_string(:add_rules), do: "addRules"
  defp type_to_string(:replace_rules), do: "replaceRules"
  defp type_to_string(:remove_rules), do: "removeRules"
  defp type_to_string(:set_mode), do: "setMode"
  defp type_to_string(:add_directories), do: "addDirectories"
  defp type_to_string(:remove_directories), do: "removeDirectories"

  defp destination_to_string(:user_settings), do: "userSettings"
  defp destination_to_string(:project_settings), do: "projectSettings"
  defp destination_to_string(:local_settings), do: "localSettings"
  defp destination_to_string(:session), do: "session"

  defp maybe_add_destination(map, %{destination: nil}), do: map

  defp maybe_add_destination(map, %{destination: dest}) do
    Map.put(map, "destination", destination_to_string(dest))
  end

  defp maybe_add_rules(map, %{type: type, rules: rules})
       when type in [:add_rules, :replace_rules, :remove_rules] and is_list(rules) do
    rules_data = Enum.map(rules, &RuleValue.to_map/1)
    Map.put(map, "rules", rules_data)
  end

  defp maybe_add_rules(map, _), do: map

  defp maybe_add_behavior(map, %{type: type, behavior: behavior})
       when type in [:add_rules, :replace_rules, :remove_rules] and not is_nil(behavior) do
    Map.put(map, "behavior", Atom.to_string(behavior))
  end

  defp maybe_add_behavior(map, _), do: map

  defp maybe_add_mode(map, %{type: :set_mode, mode: mode}) when not is_nil(mode) do
    Map.put(map, "mode", ClaudeAgentSDK.Permission.mode_to_string(mode))
  end

  defp maybe_add_mode(map, _), do: map

  defp maybe_add_directories(map, %{type: type, directories: directories})
       when type in [:add_directories, :remove_directories] and is_list(directories) do
    Map.put(map, "directories", directories)
  end

  defp maybe_add_directories(map, _), do: map
end
