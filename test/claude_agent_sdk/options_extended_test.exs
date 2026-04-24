defmodule ClaudeAgentSDK.OptionsExtendedTest do
  @moduledoc """
  TDD coverage for the newly added option fields that must mirror the Python SDK surface area.
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Config.Env
  alias ClaudeAgentSDK.{Options, TestEnvHelpers}
  alias CliSubprocessCore.ModelRegistry.Selection

  setup do
    lock_id = TestEnvHelpers.acquire_global_state_lock()

    previous = %{
      provider_backend: System.get_env(Env.provider_backend()),
      anthropic_model: System.get_env(Env.anthropic_model())
    }

    System.put_env(Env.provider_backend(), "anthropic")
    System.put_env(Env.anthropic_model(), "sonnet")

    on_exit(fn ->
      restore_env(Env.provider_backend(), previous.provider_backend)
      restore_env(Env.anthropic_model(), previous.anthropic_model)
      TestEnvHelpers.release_global_state_lock(lock_id)
    end)

    :ok
  end

  describe "budget and session flags" do
    test "max_budget_usd sets --max-budget-usd" do
      options = %Options{max_budget_usd: 12.34}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--max-budget-usd", "12.34")
    end

    test "continue_conversation adds --continue" do
      options = %Options{continue_conversation: true}
      args = Options.to_args(options)
      assert "--continue" in args
    end

    test "resume adds --resume value" do
      options = %Options{resume: "session-123"}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--resume", "session-123")
    end
  end

  describe "settings controls" do
    test "no settings and no sandbox omits --settings" do
      options = %Options{settings: nil, sandbox: nil}
      args = Options.to_args(options)
      refute "--settings" in args
    end

    test "setting_sources default omits --setting-sources" do
      options = %Options{setting_sources: nil}
      args = Options.to_args(options)

      refute "--setting-sources" in args
    end

    test "settings path maps to --settings" do
      options = %Options{settings: "/tmp/settings.json"}
      args = Options.to_args(options)
      assert flag_with_value?(args, "--settings", "/tmp/settings.json")
    end

    test "setting_sources join into comma list" do
      options = %Options{setting_sources: ["user", :project, "local"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--setting-sources", "user,project,local")
    end

    test "setting_sources empty list emits an explicit empty value" do
      options = %Options{setting_sources: []}
      args = Options.to_args(options)

      assert "--setting-sources=" in args
      refute "--setting-sources" in args
    end

    test "model payload settings patch merges into explicit settings" do
      payload =
        Selection.new(
          provider: :claude,
          requested_model: "sonnet",
          resolved_model: "sonnet",
          resolution_source: :explicit,
          provider_backend: :anthropic,
          model_source: :catalog,
          settings_patch: %{
            "sandbox" => %{"enabled" => true},
            "backend" => %{"name" => "ollama"}
          }
        )

      options = %Options{
        settings: ~s({"hello":"world","sandbox":{"enabled":false}}),
        model_payload: payload
      }

      decoded =
        options
        |> Options.to_args()
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["hello"] == "world"
      assert decoded["sandbox"]["enabled"] == true
      assert decoded["backend"]["name"] == "ollama"
    end
  end

  describe "system prompt controls" do
    test "system_prompt default emits --system-prompt with empty string" do
      options = %Options{system_prompt: nil}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--system-prompt", "")
    end

    test "system_prompt string emits --system-prompt value" do
      options = %Options{system_prompt: "You are helpful"}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--system-prompt", "You are helpful")
    end

    test "system_prompt preset with no append omits --system-prompt" do
      options = %Options{system_prompt: %{type: :preset, preset: :claude_code}}
      args = Options.to_args(options)

      refute "--system-prompt" in args
      refute "--append-system-prompt" in args
    end

    test "system_prompt preset with append emits --append-system-prompt and omits --system-prompt" do
      options = %Options{system_prompt: %{type: :preset, preset: :claude_code, append: "Do X"}}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--append-system-prompt", "Do X")
      refute "--system-prompt" in args
    end

    test "system_prompt preset supports string-keyed map" do
      options = %Options{
        system_prompt: %{"type" => "preset", "preset" => "claude_code", "append" => "Do X"}
      }

      args = Options.to_args(options)

      assert flag_with_value?(args, "--append-system-prompt", "Do X")
      refute "--system-prompt" in args
    end

    test "system_prompt file emits --system-prompt-file" do
      options = %Options{system_prompt: %{type: :file, path: "./prompts/review.txt"}}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--system-prompt-file", "./prompts/review.txt")
      refute "--system-prompt" in args
    end

    test "system_prompt preset with exclude_dynamic_sections emits CLI cache flag" do
      options = %Options{
        system_prompt: %{
          type: :preset,
          preset: :claude_code,
          exclude_dynamic_sections: true
        }
      }

      args = Options.to_args(options)

      assert "--exclude-dynamic-system-prompt-sections" in args
      refute "--system-prompt" in args
    end

    test "system_prompt preset exclude_dynamic_sections is available for initialize" do
      options = %Options{
        system_prompt: %{
          type: :preset,
          preset: :claude_code,
          exclude_dynamic_sections: true
        }
      }

      assert Options.initialize_options(options)["excludeDynamicSections"] == true
    end
  end

  describe "tool allowlists/denylists" do
    test "tools list generates --tools flag" do
      options = %Options{tools: ["Read", "Edit", "Bash"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--tools", "Read,Edit,Bash")
    end

    test "tools empty list generates --tools with empty string" do
      options = %Options{tools: []}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--tools", "")
    end

    test "tools preset generates --tools default" do
      options = %Options{tools: %{type: :preset, preset: :claude_code}}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--tools", "default")
    end

    test "tools preset supports string-keyed map" do
      options = %Options{tools: %{"type" => "preset", "preset" => "claude_code"}}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--tools", "default")
    end

    test "tools flag appears before allow/deny tool filters" do
      options = %Options{
        tools: ["Read"],
        allowed_tools: ["Bash"],
        disallowed_tools: ["Write"]
      }

      args = Options.to_args(options)

      tools_idx = Enum.find_index(args, &(&1 == "--tools"))
      allowed_idx = Enum.find_index(args, &(&1 == "--allowedTools"))
      disallowed_idx = Enum.find_index(args, &(&1 == "--disallowedTools"))

      assert is_integer(tools_idx)
      assert is_integer(allowed_idx)
      assert is_integer(disallowed_idx)
      assert tools_idx < allowed_idx
      assert tools_idx < disallowed_idx
    end

    test "allowed_tools are comma-joined to match CLI expectations" do
      options = %Options{allowed_tools: ["Read", "Write", "Bash"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--allowedTools", "Read,Write,Bash")
    end

    test "allowed_tools empty list omits flag" do
      options = %Options{allowed_tools: []}
      args = Options.to_args(options)

      refute "--allowedTools" in args
    end

    test "disallowed_tools are comma-joined to match CLI expectations" do
      options = %Options{disallowed_tools: ["Bash", "Edit"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--disallowedTools", "Bash,Edit")
    end

    test "disallowed_tools empty list omits flag" do
      options = %Options{disallowed_tools: []}
      args = Options.to_args(options)

      refute "--disallowedTools" in args
    end
  end

  describe "skills controls" do
    test "skills all injects Skill and default setting sources" do
      options = %Options{skills: "all"}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--allowedTools", "Skill")
      assert flag_with_value?(args, "--setting-sources", "user,project")
    end

    test "skills list injects Skill patterns without duplicating allowed tools" do
      options = %Options{
        skills: ["planner", "reviewer"],
        allowed_tools: ["Read", "Skill(planner)"],
        setting_sources: ["local"]
      }

      args = Options.to_args(options)

      assert flag_with_value?(args, "--allowedTools", "Read,Skill(planner),Skill(reviewer)")
      assert flag_with_value?(args, "--setting-sources", "local")
    end

    test "empty skills list disables all skill invocations via empty allowed tools addition" do
      options = %Options{skills: []}
      args = Options.to_args(options)

      refute "--allowedTools" in args
      assert flag_with_value?(args, "--setting-sources", "user,project")
    end

    test "initialize skills are sent only for explicit lists" do
      assert Options.initialize_options(%Options{skills: ["pdf", "docx"]})["skills"] == [
               "pdf",
               "docx"
             ]

      assert Options.initialize_options(%Options{skills: []})["skills"] == []
      refute Map.has_key?(Options.initialize_options(%Options{skills: "all"}), "skills")
      refute Map.has_key?(Options.initialize_options(%Options{skills: nil}), "skills")
    end
  end

  describe "task budget controls" do
    test "task_budget emits --task-budget" do
      options = %Options{task_budget: %{total: 10_000}}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--task-budget", "10000")
    end
  end

  describe "betas option" do
    test "betas list generates --betas flag" do
      options = %Options{betas: ["context-1m-2025-08-07"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--betas", "context-1m-2025-08-07")
    end

    test "multiple betas are comma-separated" do
      options = %Options{betas: ["context-1m-2025-08-07", "future-beta-2025-01-01"]}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--betas", "context-1m-2025-08-07,future-beta-2025-01-01")
    end

    test "empty betas omits flag" do
      options = %Options{betas: []}
      args = Options.to_args(options)

      refute "--betas" in args
    end

    test "nil betas omits flag" do
      options = %Options{betas: nil}
      args = Options.to_args(options)

      refute "--betas" in args
    end
  end

  describe "sandbox settings merge into settings" do
    test "sandbox-only options emit JSON --settings value" do
      options = %Options{sandbox: %{enabled: true, network: %{allowLocalBinding: true}}}
      args = Options.to_args(options)

      decoded =
        args
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["sandbox"]["enabled"] == true
      assert decoded["sandbox"]["network"]["allowLocalBinding"] == true
    end

    test "settings JSON string merges sandbox settings" do
      options = %Options{
        settings: ~s({"hello":"world"}),
        sandbox: %{enabled: true}
      }

      decoded =
        options
        |> Options.to_args()
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["hello"] == "world"
      assert decoded["sandbox"]["enabled"] == true
    end

    test "settings file path merges sandbox settings when file exists" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "claude_agent_sdk_settings_#{System.unique_integer([:positive])}.json"
        )

      File.write!(tmp_path, ~s({"from_file":true}))
      on_exit(fn -> File.rm(tmp_path) end)

      options = %Options{settings: tmp_path, sandbox: %{enabled: true}}

      decoded =
        options
        |> Options.to_args()
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["from_file"] == true
      assert decoded["sandbox"]["enabled"] == true
    end

    test "missing settings file path is ignored when sandbox present" do
      missing_path =
        Path.join(
          System.tmp_dir!(),
          "claude_agent_sdk_missing_#{System.unique_integer([:positive])}.json"
        )

      refute File.exists?(missing_path)

      options = %Options{settings: missing_path, sandbox: %{enabled: true}}

      decoded =
        options
        |> Options.to_args()
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["sandbox"]["enabled"] == true
      refute Map.has_key?(decoded, "from_file")
    end

    test "invalid JSON settings string falls back to file parsing and is ignored when missing" do
      options = %Options{settings: "{not json}", sandbox: %{enabled: true}}

      decoded =
        options
        |> Options.to_args()
        |> value_for_flag("--settings")
        |> Jason.decode!()

      assert decoded["sandbox"]["enabled"] == true
      assert Map.keys(decoded) == ["sandbox"]
    end
  end

  describe "plugins and extra args" do
    test "local plugin entries become --plugin-dir flags" do
      options = %Options{
        plugins: [
          %{type: :local, path: "/plugins/git"},
          %{type: "local", path: "/plugins/lint"}
        ]
      }

      args = Options.to_args(options)
      plugin_dirs = collect_flag_values(args, "--plugin-dir")
      assert plugin_dirs == ["/plugins/git", "/plugins/lint"]
    end

    test "extra_args map turns into raw CLI flags" do
      options = %Options{extra_args: %{"debug-to-stderr" => nil, "foo" => "bar"}}
      args = Options.to_args(options)

      assert "--debug-to-stderr" in args
      assert flag_with_value?(args, "--foo", "bar")
    end

    test "extra_args booleans follow Python semantics" do
      options =
        %Options{
          extra_args: %{
            "debug-to-stderr" => true,
            "skip-this" => false
          }
        }

      args = Options.to_args(options)

      assert "--debug-to-stderr" in args
      refute flag_with_value?(args, "--debug-to-stderr", "true")
      refute "--skip-this" in args
    end
  end

  describe "mcp config aliases" do
    test "mcp_servers accepts JSON config string" do
      json = ~s({"mcpServers":{"calc":{"type":"stdio","command":"calc","args":[]}}})
      options = %Options{mcp_servers: json}
      args = Options.to_args(options)

      assert value_for_flag(args, "--mcp-config") == json
    end

    test "mcp_servers accepts config file path" do
      path = Path.join(System.tmp_dir!(), "mcp_config_#{System.unique_integer([:positive])}.json")
      File.write!(path, "{}")

      options = %Options{mcp_servers: path}
      args = Options.to_args(options)

      assert value_for_flag(args, "--mcp-config") == path

      File.rm(path)
    end
  end

  describe "SSE and HTTP MCP server types (Python parity)" do
    test "SSE server serializes correctly" do
      options = %Options{
        mcp_servers: %{
          "weather" => %{
            type: :sse,
            url: "https://example.com/sse",
            headers: %{"Authorization" => "Bearer token"}
          }
        }
      }

      args = Options.to_args(options)
      config = args |> value_for_flag("--mcp-config") |> Jason.decode!()

      assert config["mcpServers"]["weather"]["type"] == "sse"
      assert config["mcpServers"]["weather"]["url"] == "https://example.com/sse"
      assert config["mcpServers"]["weather"]["headers"]["Authorization"] == "Bearer token"
    end

    test "HTTP server serializes correctly" do
      options = %Options{
        mcp_servers: %{
          "api" => %{
            type: :http,
            url: "https://api.example.com/mcp",
            headers: %{"X-API-Key" => "secret"}
          }
        }
      }

      args = Options.to_args(options)
      config = args |> value_for_flag("--mcp-config") |> Jason.decode!()

      assert config["mcpServers"]["api"]["type"] == "http"
      assert config["mcpServers"]["api"]["url"] == "https://api.example.com/mcp"
      assert config["mcpServers"]["api"]["headers"]["X-API-Key"] == "secret"
    end

    test "SSE server with no headers uses empty map" do
      options = %Options{
        mcp_servers: %{
          "simple" => %{
            type: :sse,
            url: "https://example.com/sse"
          }
        }
      }

      args = Options.to_args(options)
      config = args |> value_for_flag("--mcp-config") |> Jason.decode!()

      assert config["mcpServers"]["simple"]["type"] == "sse"
      assert config["mcpServers"]["simple"]["url"] == "https://example.com/sse"
      assert config["mcpServers"]["simple"]["headers"] == %{}
    end

    test "HTTP server with no headers uses empty map" do
      options = %Options{
        mcp_servers: %{
          "simple" => %{
            type: :http,
            url: "https://example.com/mcp"
          }
        }
      }

      args = Options.to_args(options)
      config = args |> value_for_flag("--mcp-config") |> Jason.decode!()

      assert config["mcpServers"]["simple"]["type"] == "http"
      assert config["mcpServers"]["simple"]["url"] == "https://example.com/mcp"
      assert config["mcpServers"]["simple"]["headers"] == %{}
    end

    test "mixed server types can coexist" do
      options = %Options{
        mcp_servers: %{
          "sse_server" => %{type: :sse, url: "https://sse.example.com"},
          "http_server" => %{type: :http, url: "https://http.example.com"},
          "stdio_server" => %{type: :stdio, command: "npx", args: ["-y", "mcp-server"]}
        }
      }

      args = Options.to_args(options)
      config = args |> value_for_flag("--mcp-config") |> Jason.decode!()

      assert config["mcpServers"]["sse_server"]["type"] == "sse"
      assert config["mcpServers"]["http_server"]["type"] == "http"
      assert config["mcpServers"]["stdio_server"]["type"] == "stdio"
    end
  end

  describe "thinking tokens" do
    test "max_thinking_tokens emits --max-thinking-tokens" do
      options = %Options{max_thinking_tokens: 1024}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--max-thinking-tokens", "1024")
    end
  end

  describe "structured outputs" do
    test "tuple output_format emits json-schema flag and json output format" do
      schema = %{"type" => "object", "properties" => %{"foo" => %{"type" => "string"}}}
      options = %Options{output_format: {:json_schema, schema}}

      args = Options.to_args(options)

      assert flag_with_value?(args, "--output-format", "json")

      json_schema_value = value_for_flag(args, "--json-schema")
      assert Jason.decode!(json_schema_value) == schema
    end

    test "map output_format emits json-schema flag and supports atom type" do
      schema = %{"type" => "object", "properties" => %{"count" => %{"type" => "integer"}}}
      options = %Options{output_format: %{type: :json_schema, schema: schema}}

      args = Options.to_args(options)

      assert flag_with_value?(args, "--output-format", "json")
      assert Jason.decode!(value_for_flag(args, "--json-schema")) == schema
    end

    test "invalid structured output raises" do
      options = %Options{output_format: {:json_schema, "not a map"}}

      assert_raise ArgumentError, fn ->
        Options.to_args(options)
      end
    end

    test "stream-json format still injects verbose flag" do
      options = %Options{output_format: :stream_json}
      args = Options.to_args(options)

      assert flag_with_value?(args, "--output-format", "stream-json")
      assert "--verbose" in args
    end
  end

  defp collect_flag_values(args, flag) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce([], fn
      [^flag, value], acc -> acc ++ [value]
      _, acc -> acc
    end)
  end

  defp flag_with_value?(args, flag, expected_value) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> false
      idx -> Enum.at(args, idx + 1) == expected_value
    end
  end

  defp value_for_flag(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
