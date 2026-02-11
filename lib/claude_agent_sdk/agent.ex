defmodule ClaudeAgentSDK.Agent do
  @moduledoc """
  Agent definition for custom agent profiles.

  An Agent represents a custom persona or role for Claude with specific:
  - Description: Human-readable description of the agent's purpose
  - Prompt: System prompt that defines the agent's behavior
  - Allowed Tools: Optional list of tools the agent can use
  - Model: Optional model specification (e.g., `"sonnet"`, `"opus"`)

  Agents enable switching between different Claude behaviors at runtime while
  maintaining conversation context.

  ## Examples

      # Define a code review agent
      code_agent = Agent.new(
        name: :code_reviewer,
        description: "Expert code reviewer",
        prompt: "You are an expert code reviewer. Analyze code for bugs, performance, and best practices.",
        allowed_tools: ["Read", "Grep"],
        model: "sonnet"
      )

      # Define a documentation agent
      doc_agent = Agent.new(
        description: "Documentation specialist",
        prompt: "You excel at writing clear, comprehensive documentation.",
        allowed_tools: ["Read", "Write"]
      )

      # Use agents in options
      options = Options.new(
        agents: %{
          coder: code_agent,
          writer: doc_agent
        },
        agent: :coder  # Start with code agent
      )

  ## Python SDK Compatibility

  Maps to Python's `AgentDefinition`:

      # Python
      AgentDefinition(
          description="Expert code reviewer",
          prompt="You are an expert...",
          tools=["Read", "Grep"],
          model="sonnet"
      )

      # Elixir equivalent
      Agent.new(
          description: "Expert code reviewer",
          prompt: "You are an expert...",
          allowed_tools: ["Read", "Grep"],
          model: "sonnet"
      )
  """

  @type t :: %__MODULE__{
          name: atom() | nil,
          description: String.t(),
          prompt: String.t(),
          allowed_tools: [String.t()] | nil,
          model: String.t() | nil
        }

  @enforce_keys [:description, :prompt]
  defstruct [
    :name,
    :description,
    :prompt,
    :allowed_tools,
    :model
  ]

  @doc """
  Creates a new Agent struct.

  ## Parameters

  - `attrs` - Keyword list of agent attributes

  ## Required Fields

  - `:description` - Description of the agent's purpose (string)
  - `:prompt` - System prompt defining the agent's behavior (string)

  ## Optional Fields

  - `:name` - Agent identifier (atom)
  - `:allowed_tools` - List of tool names the agent can use (list of strings)
  - `:model` - Model to use for this agent (string, e.g., "sonnet", "opus")

  ## Returns

  A new `t:ClaudeAgentSDK.Agent.t/0` struct.

  ## Examples

      # Minimal agent
      Agent.new(
        description: "Simple helper",
        prompt: "You are a helpful assistant"
      )

      # Complete agent
      Agent.new(
        name: :researcher,
        description: "Research specialist",
        prompt: "You excel at research and analysis",
        allowed_tools: ["WebSearch", "WebFetch"],
        model: "opus"
      )
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Validates an Agent struct.

  Ensures that required fields are present and all fields have valid values.

  ## Validation Rules

  - `description` must be present and non-empty
  - `prompt` must be present and non-empty
  - `allowed_tools` must be a list of strings (if present)
  - `model` must be a string (if present)

  ## Parameters

  - `agent` - Agent struct to validate

  ## Returns

  - `:ok` if validation succeeds
  - `{:error, reason}` if validation fails

  ## Examples

      agent = Agent.new(
        description: "Valid agent",
        prompt: "You are helpful"
      )
      Agent.validate(agent)
      #=> :ok

      invalid = Agent.new(
        description: "",
        prompt: "Prompt"
      )
      Agent.validate(invalid)
      #=> {:error, :description_required}
  """
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = agent) do
    with :ok <- validate_description(agent.description),
         :ok <- validate_prompt(agent.prompt),
         :ok <- validate_allowed_tools(agent.allowed_tools) do
      validate_model(agent.model)
    end
  end

  @doc """
  Converts an Agent to a CLI-compatible map.

  Transforms the Agent struct into a map format expected by the Claude CLI,
  converting field names to match the CLI's JSON schema:

  - `prompt` → `"prompt"`
  - `description` → `"description"`
  - `allowed_tools` → `"tools"`
  - `model` → `"model"`

  Omits nil fields from the output map.

  ## Parameters

  - `agent` - Agent struct to convert

  ## Returns

  A map with string keys suitable for JSON encoding and passing to the CLI.

  ## Examples

      agent = Agent.new(
        description: "Code reviewer",
        prompt: "You review code",
        allowed_tools: ["Read", "Grep"],
        model: "sonnet"
      )

      Agent.to_cli_map(agent)
      #=> %{
      #=>   "description" => "Code reviewer",
      #=>   "prompt" => "You review code",
      #=>   "tools" => ["Read", "Grep"],
      #=>   "model" => "sonnet"
      #=> }
  """
  @spec to_cli_map(t()) :: map()
  def to_cli_map(%__MODULE__{} = agent) do
    %{}
    |> put_if_present("description", agent.description)
    |> put_if_present("prompt", agent.prompt)
    |> put_if_present("tools", agent.allowed_tools)
    |> put_if_present("model", agent.model)
  end

  ## Private Functions

  defp validate_description(nil), do: {:error, :description_required}
  defp validate_description(""), do: {:error, :description_required}
  defp validate_description(desc) when is_binary(desc), do: :ok
  defp validate_description(_), do: {:error, :description_must_be_string}

  defp validate_prompt(nil), do: {:error, :prompt_required}
  defp validate_prompt(""), do: {:error, :prompt_required}
  defp validate_prompt(prompt) when is_binary(prompt), do: :ok
  defp validate_prompt(_), do: {:error, :prompt_must_be_string}

  defp validate_allowed_tools(nil), do: :ok
  defp validate_allowed_tools([]), do: :ok

  defp validate_allowed_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &is_binary/1) do
      :ok
    else
      {:error, :allowed_tools_must_be_strings}
    end
  end

  defp validate_allowed_tools(_), do: {:error, :allowed_tools_must_be_list}

  defp validate_model(nil), do: :ok
  defp validate_model(model) when is_binary(model), do: :ok
  defp validate_model(_), do: {:error, :model_must_be_string}

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
