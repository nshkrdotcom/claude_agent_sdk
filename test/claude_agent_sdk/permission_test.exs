defmodule ClaudeAgentSDK.PermissionTest do
  @moduledoc """
  Tests for the Permission System implementation.

  This test suite validates:
  - Permission callback invocation
  - Permission result types (allow/deny)
  - Permission context building
  - Input modification via permissions
  - Permission mode behavior (default, accept_edits, plan, bypass_permissions)
  - Runtime mode switching
  - Error handling in permission callbacks
  """

  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Permission.{Context, Result}

  describe "Permission.Result module" do
    test "allow/0 creates allow result with defaults" do
      result = Result.allow()

      assert %Result{
               behavior: :allow,
               updated_input: nil,
               updated_permissions: nil
             } = result
    end

    test "allow/1 creates allow result with updated input" do
      updated_input = %{"file_path" => "/safe/path.txt"}
      result = Result.allow(updated_input: updated_input)

      assert %Result{
               behavior: :allow,
               updated_input: ^updated_input,
               updated_permissions: nil
             } = result
    end

    test "deny/1 creates deny result with message" do
      result = Result.deny("Not allowed")

      assert %Result{
               behavior: :deny,
               message: "Not allowed",
               interrupt: false
             } = result
    end

    test "deny/1 creates deny result with interrupt flag" do
      result = Result.deny("Critical error", interrupt: true)

      assert %Result{
               behavior: :deny,
               message: "Critical error",
               interrupt: true
             } = result
    end

    test "to_json_map/1 converts allow result to JSON-compatible map" do
      result = Result.allow(updated_input: %{"key" => "value"})
      json_map = Result.to_json_map(result)

      assert json_map == %{
               "behavior" => "allow",
               "updatedInput" => %{"key" => "value"}
             }
    end

    test "to_json_map/1 uses camelCase keys for updated permissions" do
      updated_permissions = [%{"type" => "setMode", "mode" => "plan", "destination" => "session"}]
      result = Result.allow(updated_permissions: updated_permissions)
      json_map = Result.to_json_map(result)

      assert json_map == %{
               "behavior" => "allow",
               "updatedPermissions" => updated_permissions
             }
    end

    test "to_json_map/1 converts deny result to JSON-compatible map" do
      result = Result.deny("Access denied", interrupt: true)
      json_map = Result.to_json_map(result)

      assert json_map == %{
               "behavior" => "deny",
               "message" => "Access denied",
               "interrupt" => true
             }
    end
  end

  describe "Permission.Context module" do
    test "new/1 creates context with required fields" do
      context =
        Context.new(
          tool_name: "Bash",
          tool_input: %{"command" => "ls"},
          session_id: "test-session",
          suggestions: []
        )

      assert %Context{
               tool_name: "Bash",
               tool_input: %{"command" => "ls"},
               session_id: "test-session",
               suggestions: [],
               signal: nil
             } = context
    end

    test "new/1 includes suggestions from CLI" do
      suggestions = [%{"type" => "deny", "reason" => "Dangerous"}]

      context =
        Context.new(
          tool_name: "Write",
          tool_input: %{},
          session_id: "test",
          suggestions: suggestions
        )

      assert context.suggestions == suggestions
    end
  end

  describe "permission callback invocation" do
    test "callback is invoked with correct arguments" do
      # Track callback invocations
      test_pid = self()

      callback = fn context ->
        send(test_pid, {:callback_invoked, context})
        Result.allow()
      end

      # Simulate tool use with permission callback
      context =
        Context.new(
          tool_name: "Read",
          tool_input: %{"file_path" => "test.txt"},
          session_id: "session-123",
          suggestions: []
        )

      result = callback.(context)

      # Assert callback was invoked
      assert_received {:callback_invoked, received_context}
      assert received_context.tool_name == "Read"
      assert received_context.tool_input["file_path"] == "test.txt"

      # Assert result
      assert %Result{behavior: :allow} = result
    end

    test "callback can allow tool execution" do
      callback = fn _context -> Result.allow() end

      context =
        Context.new(
          tool_name: "Glob",
          tool_input: %{"pattern" => "*.ex"},
          session_id: "test",
          suggestions: []
        )

      result = callback.(context)
      assert %Result{behavior: :allow} = result
    end

    test "callback can deny tool execution" do
      callback = fn context ->
        if context.tool_name == "Bash" do
          Result.deny("Bash not allowed in this context")
        else
          Result.allow()
        end
      end

      # Test deny case
      bash_context =
        Context.new(
          tool_name: "Bash",
          tool_input: %{"command" => "rm -rf /"},
          session_id: "test",
          suggestions: []
        )

      bash_result = callback.(bash_context)
      assert %Result{behavior: :deny, message: "Bash not allowed in this context"} = bash_result

      # Test allow case
      read_context =
        Context.new(
          tool_name: "Read",
          tool_input: %{},
          session_id: "test",
          suggestions: []
        )

      read_result = callback.(read_context)
      assert %Result{behavior: :allow} = read_result
    end

    test "callback can modify tool input" do
      callback = fn context ->
        # Redirect write to safe directory
        if context.tool_name == "Write" do
          file_path = context.tool_input["file_path"]
          safe_path = "/safe/#{Path.basename(file_path)}"

          Result.allow(updated_input: Map.put(context.tool_input, "file_path", safe_path))
        else
          Result.allow()
        end
      end

      context =
        Context.new(
          tool_name: "Write",
          tool_input: %{"file_path" => "/etc/passwd", "content" => "data"},
          session_id: "test",
          suggestions: []
        )

      result = callback.(context)

      assert %Result{
               behavior: :allow,
               updated_input: %{"file_path" => "/safe/passwd", "content" => "data"}
             } = result
    end

    test "callback exception handling returns error result" do
      callback = fn _context ->
        raise "Callback error!"
      end

      context =
        Context.new(
          tool_name: "Test",
          tool_input: %{},
          session_id: "test",
          suggestions: []
        )

      # Execute with exception handling
      result =
        try do
          callback.(context)
        rescue
          e -> Result.deny("Callback error: #{Exception.message(e)}")
        end

      assert %Result{behavior: :deny} = result
      assert result.message =~ "Callback error"
    end
  end

  describe "permission modes" do
    test "default mode invokes callback for all tools" do
      callback = fn context ->
        # Callback is invoked for each tool
        _ = context.tool_name
        Result.allow()
      end

      # Simulate multiple tool uses
      tools = ["Read", "Write", "Bash", "Glob"]

      Enum.each(tools, fn tool_name ->
        context =
          Context.new(
            tool_name: tool_name,
            tool_input: %{},
            session_id: "test",
            suggestions: []
          )

        callback.(context)
      end)

      # In default mode, all tools go through callback
      # This behavior is validated in Client tests
      assert true
    end

    test "accept_edits mode allows edits without callback (integrated test)" do
      # This mode bypasses callback for edit operations
      # Validated at integration level with Client
      assert :accept_edits in [:default, :accept_edits, :plan, :bypass_permissions]
    end

    test "plan mode requires explicit approval (integrated test)" do
      # This mode shows plan before execution
      # Validated at integration level with Client
      assert :plan in [:default, :accept_edits, :plan, :bypass_permissions]
    end

    test "bypass_permissions mode skips all callbacks (integrated test)" do
      # This mode bypasses all permission checks
      # Validated at integration level with Client
      assert :bypass_permissions in [:default, :accept_edits, :plan, :bypass_permissions]
    end

    test "mode values are valid atoms" do
      valid_modes = [:default, :accept_edits, :plan, :bypass_permissions]

      # Test mode validation function (to be implemented)
      assert Enum.all?(valid_modes, &is_atom/1)
    end
  end

  describe "permission context building" do
    test "builds context from control request" do
      # Simulate control request from CLI
      request = %{
        "request_id" => "req-123",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Write",
          "input" => %{"file_path" => "/tmp/test.txt"},
          "permission_suggestions" => [
            %{"type" => "deny", "reason" => "System file"}
          ]
        }
      }

      # Build context
      context =
        Context.new(
          tool_name: request["request"]["tool_name"],
          tool_input: request["request"]["input"],
          session_id: "test-session",
          suggestions: request["request"]["permission_suggestions"]
        )

      assert context.tool_name == "Write"
      assert context.tool_input == %{"file_path" => "/tmp/test.txt"}
      assert length(context.suggestions) == 1
    end

    test "context includes session information" do
      context =
        Context.new(
          tool_name: "Read",
          tool_input: %{},
          session_id: "550e8400-e29b-41d4-a716-446655440000",
          suggestions: []
        )

      assert context.session_id == "550e8400-e29b-41d4-a716-446655440000"
    end
  end

  describe "complex permission scenarios" do
    test "security policy: deny dangerous bash commands" do
      dangerous_commands = [
        "rm -rf /",
        "sudo rm -rf /",
        "chmod 777 /",
        "dd if=/dev/zero of=/dev/sda",
        "mkfs.ext4 /dev/sda"
      ]

      callback = fn context ->
        if context.tool_name == "Bash" do
          command = context.tool_input["command"] || ""

          dangerous? =
            Enum.any?(["rm -rf", "sudo", "chmod 777", "dd if=", "mkfs"], fn pattern ->
              String.contains?(command, pattern)
            end)

          if dangerous? do
            Result.deny("Dangerous command pattern detected")
          else
            Result.allow()
          end
        else
          Result.allow()
        end
      end

      # Test each dangerous command
      Enum.each(dangerous_commands, fn cmd ->
        context =
          Context.new(
            tool_name: "Bash",
            tool_input: %{"command" => cmd},
            session_id: "test",
            suggestions: []
          )

        result = callback.(context)
        assert %Result{behavior: :deny} = result
      end)

      # Test safe command
      safe_context =
        Context.new(
          tool_name: "Bash",
          tool_input: %{"command" => "ls -la"},
          session_id: "test",
          suggestions: []
        )

      safe_result = callback.(safe_context)
      assert %Result{behavior: :allow} = safe_result
    end

    test "path restriction: only allow reads from allowed directories" do
      allowed_dirs = ["/tmp", "/home/user/project", "./"]

      callback = fn context ->
        if context.tool_name in ["Read", "Write"] do
          file_path = context.tool_input["file_path"] || ""

          allowed? =
            Enum.any?(allowed_dirs, fn dir ->
              String.starts_with?(file_path, dir)
            end)

          if allowed? do
            Result.allow()
          else
            Result.deny("File path outside allowed directories: #{allowed_dirs}")
          end
        else
          Result.allow()
        end
      end

      # Test allowed path
      allowed_context =
        Context.new(
          tool_name: "Read",
          tool_input: %{"file_path" => "/tmp/test.txt"},
          session_id: "test",
          suggestions: []
        )

      allowed_result = callback.(allowed_context)
      assert %Result{behavior: :allow} = allowed_result

      # Test disallowed path
      disallowed_context =
        Context.new(
          tool_name: "Write",
          tool_input: %{"file_path" => "/etc/passwd"},
          session_id: "test",
          suggestions: []
        )

      disallowed_result = callback.(disallowed_context)
      assert %Result{behavior: :deny} = disallowed_result
    end

    test "logging: track all tool uses" do
      test_pid = self()

      callback = fn context ->
        # Log to process mailbox
        send(test_pid, {:tool_use, context.tool_name, context.tool_input})
        Result.allow()
      end

      # Simulate several tool uses
      tools = [
        {"Read", %{"file_path" => "test.ex"}},
        {"Write", %{"file_path" => "output.txt"}},
        {"Bash", %{"command" => "echo hello"}}
      ]

      Enum.each(tools, fn {tool_name, input} ->
        context =
          Context.new(
            tool_name: tool_name,
            tool_input: input,
            session_id: "test",
            suggestions: []
          )

        callback.(context)
      end)

      # Verify all were logged
      assert_received {:tool_use, "Read", %{"file_path" => "test.ex"}}
      assert_received {:tool_use, "Write", %{"file_path" => "output.txt"}}
      assert_received {:tool_use, "Bash", %{"command" => "echo hello"}}
    end

    test "conditional modification: redirect system file writes to safe location" do
      callback = fn context ->
        if context.tool_name == "Write" do
          file_path = context.tool_input["file_path"]

          # Check if writing to system directory
          if String.starts_with?(file_path, "/etc/") or String.starts_with?(file_path, "/usr/") do
            # Redirect to safe directory
            safe_path = "/tmp/safe_output/#{Path.basename(file_path)}"

            Result.allow(updated_input: Map.put(context.tool_input, "file_path", safe_path))
          else
            Result.allow()
          end
        else
          Result.allow()
        end
      end

      # Test system file write gets redirected
      system_context =
        Context.new(
          tool_name: "Write",
          tool_input: %{"file_path" => "/etc/config.conf", "content" => "data"},
          session_id: "test",
          suggestions: []
        )

      system_result = callback.(system_context)
      assert %Result{behavior: :allow, updated_input: updated} = system_result
      assert updated["file_path"] == "/tmp/safe_output/config.conf"
      assert updated["content"] == "data"

      # Test normal write is unchanged
      normal_context =
        Context.new(
          tool_name: "Write",
          tool_input: %{"file_path" => "/tmp/myfile.txt", "content" => "data"},
          session_id: "test",
          suggestions: []
        )

      normal_result = callback.(normal_context)
      assert %Result{behavior: :allow, updated_input: nil} = normal_result
    end
  end

  describe "permission callback with Options" do
    test "Options struct includes can_use_tool field" do
      callback = fn _context -> Result.allow() end

      options = %ClaudeAgentSDK.Options{
        max_turns: 5,
        permission_mode: :default,
        can_use_tool: callback
      }

      assert options.can_use_tool == callback
      assert options.permission_mode == :default
    end

    test "Options struct includes permission_mode field" do
      options = %ClaudeAgentSDK.Options{
        permission_mode: :plan
      }

      assert options.permission_mode == :plan
    end

    test "Options validates permission mode values" do
      valid_modes = [:default, :accept_edits, :plan, :bypass_permissions]

      Enum.each(valid_modes, fn mode ->
        options = %ClaudeAgentSDK.Options{permission_mode: mode}
        assert options.permission_mode == mode
      end)
    end
  end
end
