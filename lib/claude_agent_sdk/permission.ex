defmodule ClaudeAgentSDK.Permission do
  @moduledoc """
  Permission System for Claude Agent SDK.

  This module provides a structured permission system for controlling tool execution
  at runtime through callbacks and permission modes.

  ## Permission Modes

  The SDK supports six permission modes that control how tool permissions are handled:

  - `:default` - All tools go through the permission callback
  - `:accept_edits` - Edit operations (Write, Edit, MultiEdit) are auto-allowed
  - `:plan` - Claude creates a plan, shows it to user, then executes after approval
  - `:bypass_permissions` - All tools are allowed without callback invocation
  - `:delegate` - Delegate tool execution to the SDK (CLI does not run built-in tools)
  - `:dont_ask` - Do not prompt for permissions; tools proceed without callback

  ## Permission Callbacks

  Permission callbacks allow fine-grained control over tool execution. They receive
  context about the tool being used and return a permission result.

  ### Callback Signature

      (Context.t() -> Result.t())

  ### Example

      callback = fn context ->
        case context.tool_name do
          "Bash" ->
            if String.contains?(context.tool_input["command"], "rm -rf") do
              Result.deny("Dangerous command detected")
            else
              Result.allow()
            end

          "Write" ->
            # Redirect system file writes to safe location
            file_path = context.tool_input["file_path"]
            if String.starts_with?(file_path, "/etc/") do
              safe_path = "/tmp/safe_output/" <> Path.basename(file_path)
              Result.allow(updated_input: %{context.tool_input | "file_path" => safe_path})
            else
              Result.allow()
            end

          _ ->
            Result.allow()
        end
      end

      options = %Options{
        can_use_tool: callback,
        permission_mode: :default
      }

  ## Runtime Mode Switching

  Permission mode can be changed at runtime using `Client.set_permission_mode/2`:

      {:ok, client} = Client.start_link(options)

      # Switch to plan mode
      Client.set_permission_mode(client, :plan)

      # Switch back to default
      Client.set_permission_mode(client, :default)

  ## Integration with Hooks

  The permission system integrates with the existing hooks system. Permission
  callbacks are invoked via the control protocol when the CLI requests permission
  to use a tool. If the CLI does not emit `can_use_tool` requests, the SDK
  automatically invokes the callback via a PreToolUse hook when possible.
  In that hook-based path, `updated_permissions` updates are ignored.
  When `can_use_tool` is set, the SDK enables partial messages and configures
  the CLI permission prompt tool to `\"stdio\"` internally.

  See:
  - `ClaudeAgentSDK.Permission.Context` - Permission context structure
  - `ClaudeAgentSDK.Permission.Result` - Permission result types
  """

  alias ClaudeAgentSDK.Permission.{Context, Result}

  @typedoc """
  Permission mode controlling how tool permissions are handled.
  """
  @type permission_mode ::
          :default | :accept_edits | :plan | :bypass_permissions | :delegate | :dont_ask

  @typedoc """
  Permission callback function type.

  Receives permission context and returns permission result.
  """
  @type callback :: (Context.t() -> Result.t())

  @doc """
  Returns all valid permission modes.

  ## Examples

      iex> ClaudeAgentSDK.Permission.valid_modes()
      [:default, :accept_edits, :plan, :bypass_permissions, :delegate, :dont_ask]
  """
  @spec valid_modes() :: [permission_mode()]
  def valid_modes do
    [:default, :accept_edits, :plan, :bypass_permissions, :delegate, :dont_ask]
  end

  @doc """
  Validates a permission mode.

  Returns `true` if the mode is valid, `false` otherwise.

  ## Examples

      iex> ClaudeAgentSDK.Permission.valid_mode?(:default)
      true

      iex> ClaudeAgentSDK.Permission.valid_mode?(:invalid)
      false
  """
  @spec valid_mode?(term()) :: boolean()
  def valid_mode?(mode) when is_atom(mode) do
    mode in valid_modes()
  end

  def valid_mode?(_), do: false

  @doc """
  Converts permission mode atom to CLI string format.

  ## Examples

      iex> ClaudeAgentSDK.Permission.mode_to_string(:accept_edits)
      "acceptEdits"

      iex> ClaudeAgentSDK.Permission.mode_to_string(:default)
      "default"
  """
  @spec mode_to_string(permission_mode()) :: String.t()
  def mode_to_string(:accept_edits), do: "acceptEdits"
  def mode_to_string(:bypass_permissions), do: "bypassPermissions"
  def mode_to_string(:dont_ask), do: "dontAsk"
  def mode_to_string(:delegate), do: "delegate"
  def mode_to_string(mode) when is_atom(mode), do: Atom.to_string(mode)

  @doc """
  Converts CLI permission mode string to atom.

  Returns `nil` for unknown mode strings.

  ## Examples

      iex> ClaudeAgentSDK.Permission.string_to_mode("acceptEdits")
      :accept_edits

      iex> ClaudeAgentSDK.Permission.string_to_mode("invalid")
      nil
  """
  @spec string_to_mode(String.t()) :: permission_mode() | nil
  def string_to_mode("default"), do: :default
  def string_to_mode("acceptEdits"), do: :accept_edits
  def string_to_mode("plan"), do: :plan
  def string_to_mode("bypassPermissions"), do: :bypass_permissions
  def string_to_mode("delegate"), do: :delegate
  def string_to_mode("dontAsk"), do: :dont_ask
  def string_to_mode(_), do: nil

  @doc """
  Validates a permission callback function.

  Returns `:ok` if the callback is valid, `{:error, reason}` otherwise.

  ## Examples

      iex> callback = fn _context -> Result.allow() end
      iex> ClaudeAgentSDK.Permission.validate_callback(callback)
      :ok

      iex> ClaudeAgentSDK.Permission.validate_callback("not a function")
      {:error, "Permission callback must be a function"}
  """
  @spec validate_callback(term()) :: :ok | {:error, String.t()}
  def validate_callback(callback) when is_function(callback, 1), do: :ok

  def validate_callback(_),
    do: {:error, "Permission callback must be a function with arity 1"}
end
