defmodule ClaudeAgentSDK.Permission.Context do
  @moduledoc """
  Permission context passed to permission callbacks.

  The context contains information about the tool being used, including:
  - Tool name
  - Tool input parameters
  - Session identifier
  - Permission suggestions from the CLI
  - Abort signal (reserved for future use)

  ## Structure

      %Context{
        tool_name: "Bash",
        tool_input: %{"command" => "ls -la"},
        session_id: "550e8400-e29b-41d4-a716-446655440000",
        suggestions: [],
        signal: nil
      }

  ## Usage in Callbacks

      def my_permission_callback(context) do
        case context.tool_name do
          "Bash" ->
            command = context.tool_input["command"]
            if safe_command?(command) do
              Result.allow()
            else
              Result.deny("Command not allowed")
            end

          "Write" ->
            file_path = context.tool_input["file_path"]
            if allowed_path?(file_path) do
              Result.allow()
            else
              Result.deny("Path not allowed")
            end

          _ ->
            Result.allow()
        end
      end

  ## Permission Suggestions

  The `suggestions` field contains permission update suggestions from the CLI.
  These are hints about what permission rules might be appropriate:

      [
        %{
          "type" => "deny",
          "reason" => "System file access detected",
          "tool_name" => "Write"
        }
      ]

  Your callback can use these suggestions to make informed decisions or
  ignore them entirely.
  """

  @typedoc """
  Permission context struct.

  Fields:
  - `tool_name` - Name of the tool being invoked (e.g., "Bash", "Write", "Read")
  - `tool_input` - Map of input parameters for the tool
  - `session_id` - Unique identifier for the current session
  - `suggestions` - List of permission update suggestions from CLI
  - `signal` - Optional abort signal reference (reserved for future use)
  """
  @type t :: %__MODULE__{
          tool_name: String.t(),
          tool_input: map(),
          session_id: String.t(),
          suggestions: [map()],
          blocked_path: String.t() | nil,
          signal: ClaudeAgentSDK.AbortSignal.t() | nil
        }

  @enforce_keys [:tool_name, :tool_input, :session_id]
  defstruct [:tool_name, :tool_input, :session_id, :signal, :blocked_path, suggestions: []]

  @doc """
  Creates a new permission context.

  ## Parameters

  - `attrs` - Keyword list of context attributes

  ## Required Attributes

  - `:tool_name` - Tool being invoked
  - `:tool_input` - Tool input parameters
  - `:session_id` - Session identifier

  ## Optional Attributes

  - `:suggestions` - Permission suggestions from CLI (default: [])
  - `:signal` - Abort signal reference (default: nil)

  ## Examples

      Context.new(
        tool_name: "Bash",
        tool_input: %{"command" => "echo hello"},
        session_id: "550e8400-e29b-41d4-a716-446655440000"
      )

      Context.new(
        tool_name: "Write",
        tool_input: %{"file_path" => "/tmp/test.txt", "content" => "data"},
        session_id: "test-session",
        suggestions: [%{"type" => "deny"}]
      )
  """
  @spec new(keyword()) :: t()
  def new(attrs) when is_list(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Builds a permission context from a control protocol request.

  ## Parameters

  - `request` - Control request map from CLI
  - `session_id` - Current session identifier

  ## Examples

      request = %{
        "request_id" => "req-123",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Read",
          "input" => %{"file_path" => "test.txt"},
          "permission_suggestions" => []
        }
      }

      Context.from_control_request(request, "session-id")
  """
  @spec from_control_request(map(), String.t()) :: t()
  def from_control_request(request, session_id) when is_map(request) and is_binary(session_id) do
    request_data = request["request"] || %{}

    new(
      tool_name: request_data["tool_name"] || "",
      tool_input: request_data["input"] || %{},
      session_id: session_id,
      suggestions: request_data["permission_suggestions"] || []
    )
  end
end
