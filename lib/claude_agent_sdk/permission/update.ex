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
  alias ClaudeAgentSDK.Schema
  alias CliSubprocessCore.Schema.Conventions

  @update_type_aliases %{
    :add_rules => :add_rules,
    :replace_rules => :replace_rules,
    :remove_rules => :remove_rules,
    :set_mode => :set_mode,
    :add_directories => :add_directories,
    :remove_directories => :remove_directories,
    "addRules" => :add_rules,
    "replaceRules" => :replace_rules,
    "removeRules" => :remove_rules,
    "setMode" => :set_mode,
    "addDirectories" => :add_directories,
    "removeDirectories" => :remove_directories,
    "add_rules" => :add_rules,
    "replace_rules" => :replace_rules,
    "remove_rules" => :remove_rules,
    "set_mode" => :set_mode,
    "add_directories" => :add_directories,
    "remove_directories" => :remove_directories
  }
  @destination_aliases %{
    :user_settings => :user_settings,
    :project_settings => :project_settings,
    :local_settings => :local_settings,
    :session => :session,
    "userSettings" => :user_settings,
    "projectSettings" => :project_settings,
    "localSettings" => :local_settings,
    "session" => :session,
    "user_settings" => :user_settings,
    "project_settings" => :project_settings,
    "local_settings" => :local_settings
  }

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
          destination: destination() | nil,
          extra: map()
        }

  @known_fields ["type", "rules", "behavior", "mode", "directories", "destination"]
  @schema Zoi.map(
            %{
              "type" => Zoi.any() |> Zoi.transform({__MODULE__, :normalize_update_type, []}),
              "rules" => Zoi.optional(Zoi.nullish(Zoi.array(Zoi.any()))),
              "behavior" =>
                Zoi.optional(
                  Zoi.nullish(Zoi.any() |> Zoi.transform({__MODULE__, :normalize_behavior, []}))
                ),
              "mode" =>
                Zoi.optional(
                  Zoi.nullish(Zoi.any() |> Zoi.transform({__MODULE__, :normalize_mode, []}))
                ),
              "directories" =>
                Zoi.optional(Zoi.nullish(Zoi.array(Conventions.trimmed_string() |> Zoi.min(1)))),
              "destination" =>
                Zoi.optional(
                  Zoi.nullish(
                    Zoi.any()
                    |> Zoi.transform({__MODULE__, :normalize_destination, []})
                  )
                )
            },
            unrecognized_keys: :preserve
          )

  @enforce_keys [:type]
  defstruct [:type, :rules, :behavior, :mode, :directories, :destination, extra: %{}]

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

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
    attrs =
      opts
      |> Enum.into(%{})
      |> Map.put("type", type)

    parse!(attrs)
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
    |> Map.merge(update.extra)
  end

  @spec parse(map() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_permission_update, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = update), do: {:ok, update}

  def parse(map) when is_map(map) do
    case Schema.parse(@schema, normalize_keys(map), :invalid_permission_update) do
      {:ok, parsed} ->
        {known, extra} = Schema.split_extra(parsed, @known_fields)

        {:ok,
         %__MODULE__{
           type: Map.fetch!(known, "type"),
           rules: parse_rules(Map.get(known, "rules")),
           behavior: Map.get(known, "behavior"),
           mode: Map.get(known, "mode"),
           directories: Map.get(known, "directories"),
           destination: Map.get(known, "destination"),
           extra: extra
         }}

      {:error, {:invalid_permission_update, details}} ->
        {:error, {:invalid_permission_update, details}}
    end
  rescue
    error in [ArgumentError] ->
      {:error,
       {:invalid_permission_update,
        %{
          message: Exception.message(error),
          errors: %{},
          issues: [%{code: :invalid, message: Exception.message(error), path: []}]
        }}}
  end

  @spec parse!(map() | t()) :: t()
  def parse!(%__MODULE__{} = update), do: update

  def parse!(map) when is_map(map) do
    parsed = Schema.parse!(@schema, normalize_keys(map), :invalid_permission_update)
    {known, extra} = Schema.split_extra(parsed, @known_fields)

    %__MODULE__{
      type: Map.fetch!(known, "type"),
      rules: parse_rules(Map.get(known, "rules")),
      behavior: Map.get(known, "behavior"),
      mode: Map.get(known, "mode"),
      directories: Map.get(known, "directories"),
      destination: Map.get(known, "destination"),
      extra: extra
    }
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

  @doc false
  def normalize_update_type(value, opts), do: normalize_update_type(value, [], opts)

  @doc false
  def normalize_update_type(value, _args, _opts) do
    normalize_alias(value, @update_type_aliases, "invalid permission update type")
  end

  @doc false
  def normalize_behavior(value, opts), do: normalize_behavior(value, [], opts)

  @doc false
  def normalize_behavior(value, _args, _opts) do
    case value do
      :allow -> {:ok, :allow}
      :deny -> {:ok, :deny}
      :ask -> {:ok, :ask}
      "allow" -> {:ok, :allow}
      "deny" -> {:ok, :deny}
      "ask" -> {:ok, :ask}
      other -> {:error, "invalid permission behavior: #{inspect(other)}"}
    end
  end

  @doc false
  def normalize_destination(value, opts), do: normalize_destination(value, [], opts)

  @doc false
  def normalize_destination(value, _args, _opts) do
    normalize_alias(value, @destination_aliases, "invalid permission destination")
  end

  @doc false
  def normalize_mode(value, opts), do: normalize_mode(value, [], opts)

  @doc false
  def normalize_mode(value, _args, _opts) do
    cond do
      ClaudeAgentSDK.Permission.valid_mode?(value) ->
        {:ok, value}

      is_binary(value) ->
        case ClaudeAgentSDK.Permission.string_to_mode(value) do
          nil -> {:error, "invalid permission mode: #{inspect(value)}"}
          mode -> {:ok, mode}
        end

      true ->
        {:error, "invalid permission mode: #{inspect(value)}"}
    end
  end

  defp normalize_alias(value, aliases, message) do
    case Map.fetch(aliases, value) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, "#{message}: #{inspect(value)}"}
    end
  end

  defp parse_rules(nil), do: nil

  defp parse_rules(rules) when is_list(rules) do
    Enum.map(rules, fn rule ->
      case RuleValue.parse(rule) do
        {:ok, parsed} ->
          parsed

        {:error, {:invalid_permission_rule_value, details}} ->
          raise ArgumentError, details.message
      end
    end)
  end

  defp normalize_keys(map) do
    Enum.reduce(map, %{}, fn
      {:type, value}, acc -> Map.put(acc, "type", value)
      {:rules, value}, acc -> Map.put(acc, "rules", value)
      {:behavior, value}, acc -> Map.put(acc, "behavior", value)
      {:mode, value}, acc -> Map.put(acc, "mode", value)
      {:directories, value}, acc -> Map.put(acc, "directories", value)
      {:destination, value}, acc -> Map.put(acc, "destination", value)
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
