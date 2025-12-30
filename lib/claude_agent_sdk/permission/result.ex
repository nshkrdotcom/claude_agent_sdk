defmodule ClaudeAgentSDK.Permission.Result do
  @moduledoc """
  Permission result returned by permission callbacks.

  A permission result indicates whether a tool should be allowed to execute,
  and optionally modifies the tool's input parameters or permission rules.

  ## Result Types

  ### Allow

  Permits the tool to execute:

      Result.allow()
      Result.allow(updated_input: %{"file_path" => "/safe/path.txt"})

  ### Deny

  Blocks the tool from executing:

      Result.deny("Command not allowed")
      Result.deny("Critical violation", interrupt: true)

  ## Fields

  ### For Allow Results

  - `behavior` - Always `:allow`
  - `updated_input` - Optional modified tool input (map)
  - `updated_permissions` - Optional permission rule updates (list)

  ### For Deny Results

  - `behavior` - Always `:deny`
  - `message` - Explanation for denial (string)
  - `interrupt` - If true, stops entire agent execution (boolean)

  ## Examples

      # Simple allow
      Result.allow()

      # Allow with input modification
      Result.allow(updated_input: %{"command" => "ls -la /safe/dir"})

      # Simple deny
      Result.deny("Tool not allowed in this context")

      # Deny with interrupt
      Result.deny("Security violation detected", interrupt: true)
  """

  alias ClaudeAgentSDK.Permission.Update

  @typedoc """
  Permission result behavior.
  """
  @type behavior :: :allow | :deny

  @typedoc """
  Permission result struct.

  For allow results:
  - `behavior` - `:allow`
  - `updated_input` - Optional modified tool input
  - `updated_permissions` - Optional permission updates (list of Update.t() or maps)

  For deny results:
  - `behavior` - `:deny`
  - `message` - Explanation for denial
  - `interrupt` - Whether to stop entire execution
  """
  @type t :: %__MODULE__{
          behavior: behavior(),
          updated_input: map() | nil,
          updated_permissions: [Update.t() | map()] | nil,
          message: String.t() | nil,
          interrupt: boolean()
        }

  defstruct behavior: :allow,
            updated_input: nil,
            updated_permissions: nil,
            message: nil,
            interrupt: false

  @doc """
  Creates an allow permission result.

  ## Parameters

  - `opts` - Keyword list of options

  ## Options

  - `:updated_input` - Modified tool input (map)
  - `:updated_permissions` - Permission rule updates (list of maps)

  ## Examples

      # Simple allow
      Result.allow()

      # Allow with input modification
      Result.allow(updated_input: %{"file_path" => "/safe/output.txt"})

      # Allow with permission updates
      Result.allow(
        updated_permissions: [
          %{type: "addRules", tool_name: "Bash", behavior: "deny"}
        ]
      )
  """
  @spec allow(keyword()) :: t()
  def allow(opts \\ []) do
    %__MODULE__{
      behavior: :allow,
      updated_input: Keyword.get(opts, :updated_input),
      updated_permissions: Keyword.get(opts, :updated_permissions)
    }
  end

  @doc """
  Creates a deny permission result.

  ## Parameters

  - `message` - Explanation for the denial (required)
  - `opts` - Keyword list of options

  ## Options

  - `:interrupt` - If true, stops entire agent execution (default: false)

  ## Examples

      # Simple deny
      Result.deny("Tool not allowed")

      # Deny with interrupt
      Result.deny("Security policy violation", interrupt: true)
  """
  @spec deny(String.t(), keyword()) :: t()
  def deny(message, opts \\ []) when is_binary(message) do
    %__MODULE__{
      behavior: :deny,
      message: message,
      interrupt: Keyword.get(opts, :interrupt, false)
    }
  end

  @doc """
  Converts a permission result to a JSON-compatible map for the CLI.

  ## Examples

      iex> result = Result.allow()
      iex> Result.to_json_map(result)
      %{"behavior" => "allow"}

      iex> result = Result.deny("Not allowed")
      iex> Result.to_json_map(result)
      %{"behavior" => "deny", "message" => "Not allowed", "interrupt" => false}

      iex> result = Result.allow(updated_input: %{"key" => "value"})
      iex> Result.to_json_map(result)
      %{"behavior" => "allow", "updatedInput" => %{"key" => "value"}}
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{behavior: :allow} = result) do
    base = %{"behavior" => "allow"}

    base
    |> maybe_add("updatedInput", result.updated_input)
    |> maybe_add_permissions(result.updated_permissions)
  end

  def to_json_map(%__MODULE__{behavior: :deny} = result) do
    %{
      "behavior" => "deny",
      "message" => result.message || "",
      "interrupt" => result.interrupt
    }
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_permissions(map, nil), do: map

  defp maybe_add_permissions(map, permissions) when is_list(permissions) do
    serialized =
      Enum.map(permissions, fn
        %Update{} = update ->
          Update.to_map(update)

        m when is_map(m) ->
          m
      end)

    Map.put(map, "updatedPermissions", serialized)
  end

  @doc """
  Validates a permission result.

  Returns `:ok` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> Result.validate(Result.allow())
      :ok

      iex> Result.validate(Result.deny("Reason"))
      :ok

      iex> Result.validate(%{})
      {:error, "Result must be a ClaudeAgentSDK.Permission.Result struct"}
  """
  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{behavior: :allow} = result) do
    cond do
      not is_nil(result.updated_input) and not is_map(result.updated_input) ->
        {:error, "updated_input must be a map"}

      not is_nil(result.updated_permissions) and not is_list(result.updated_permissions) ->
        {:error, "updated_permissions must be a list"}

      true ->
        :ok
    end
  end

  def validate(%__MODULE__{behavior: :deny} = result) do
    cond do
      is_nil(result.message) or not is_binary(result.message) ->
        {:error, "Deny result must have a message"}

      not is_boolean(result.interrupt) ->
        {:error, "interrupt must be a boolean"}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, "Result must be a ClaudeAgentSDK.Permission.Result struct"}
end
