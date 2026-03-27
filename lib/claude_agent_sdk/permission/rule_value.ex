defmodule ClaudeAgentSDK.Permission.RuleValue do
  @moduledoc """
  Permission rule value struct.

  Represents a single permission rule with a tool name and optional rule content
  that defines the permission pattern.

  ## Examples

      # Simple tool permission
      RuleValue.new("Bash")

      # Tool permission with pattern
      RuleValue.new("Bash", "echo *")

      # File write permission with path pattern
      RuleValue.new("Write", "/tmp/**")
  """

  alias ClaudeAgentSDK.Schema
  alias CliSubprocessCore.Schema.Conventions

  @typedoc """
  Permission rule value struct.
  """
  @type t :: %__MODULE__{
          tool_name: String.t(),
          rule_content: String.t() | nil,
          extra: map()
        }

  @known_fields ["toolName", "ruleContent"]
  @schema Zoi.map(
            %{
              "toolName" => Conventions.trimmed_string() |> Zoi.min(1),
              "ruleContent" => Conventions.optional_trimmed_string()
            },
            unrecognized_keys: :preserve
          )

  @enforce_keys [:tool_name]
  defstruct [:tool_name, :rule_content, extra: %{}]

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new rule value.

  ## Parameters

  - `tool_name` - Name of the tool this rule applies to
  - `rule_content` - Optional content pattern for the rule

  ## Examples

      iex> RuleValue.new("Bash")
      %RuleValue{tool_name: "Bash", rule_content: nil}

      iex> RuleValue.new("Bash", "echo *")
      %RuleValue{tool_name: "Bash", rule_content: "echo *"}
  """
  @spec new(String.t(), String.t() | nil) :: t()
  def new(tool_name, rule_content \\ nil) do
    parse!(%{"toolName" => tool_name, "ruleContent" => rule_content})
  end

  @spec parse(map() | t()) ::
          {:ok, t()}
          | {:error, {:invalid_permission_rule_value, CliSubprocessCore.Schema.error_detail()}}
  def parse(%__MODULE__{} = value), do: {:ok, value}

  def parse(map) when is_map(map) do
    case Schema.parse(@schema, normalize_keys(map), :invalid_permission_rule_value) do
      {:ok, parsed} ->
        {known, extra} = Schema.split_extra(parsed, @known_fields)

        {:ok,
         %__MODULE__{
           tool_name: Map.fetch!(known, "toolName"),
           rule_content: Map.get(known, "ruleContent"),
           extra: extra
         }}

      {:error, {:invalid_permission_rule_value, details}} ->
        {:error, {:invalid_permission_rule_value, details}}
    end
  end

  @spec parse!(map() | t()) :: t()
  def parse!(%__MODULE__{} = value), do: value

  def parse!(map) when is_map(map) do
    parsed = Schema.parse!(@schema, normalize_keys(map), :invalid_permission_rule_value)
    {known, extra} = Schema.split_extra(parsed, @known_fields)

    %__MODULE__{
      tool_name: Map.fetch!(known, "toolName"),
      rule_content: Map.get(known, "ruleContent"),
      extra: extra
    }
  end

  @doc """
  Converts a rule value to a map for the control protocol.

  ## Examples

      iex> RuleValue.new("Bash", "echo *") |> RuleValue.to_map()
      %{"toolName" => "Bash", "ruleContent" => "echo *"}

      iex> RuleValue.new("Bash") |> RuleValue.to_map()
      %{"toolName" => "Bash", "ruleContent" => nil}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{tool_name: tool_name, rule_content: rule_content, extra: extra}) do
    %{
      "toolName" => tool_name,
      "ruleContent" => rule_content
    }
    |> Map.merge(extra)
  end

  defp normalize_keys(map) do
    Enum.reduce(map, %{}, fn
      {:tool_name, value}, acc -> Map.put(acc, "toolName", value)
      {"tool_name", value}, acc -> Map.put(acc, "toolName", value)
      {:toolName, value}, acc -> Map.put(acc, "toolName", value)
      {:rule_content, value}, acc -> Map.put(acc, "ruleContent", value)
      {"rule_content", value}, acc -> Map.put(acc, "ruleContent", value)
      {:ruleContent, value}, acc -> Map.put(acc, "ruleContent", value)
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
