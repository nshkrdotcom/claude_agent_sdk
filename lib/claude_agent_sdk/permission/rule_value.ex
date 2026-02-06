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

  @typedoc """
  Permission rule value struct.
  """
  @type t :: %__MODULE__{
          tool_name: String.t(),
          rule_content: String.t() | nil
        }

  @enforce_keys [:tool_name]
  defstruct [:tool_name, :rule_content]

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
    %__MODULE__{
      tool_name: tool_name,
      rule_content: rule_content
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
  def to_map(%__MODULE__{tool_name: tool_name, rule_content: rule_content}) do
    %{
      "toolName" => tool_name,
      "ruleContent" => rule_content
    }
  end
end
