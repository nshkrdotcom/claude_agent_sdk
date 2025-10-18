$ mix test
     warning: function handle_can_use_tool_request/3 is unused
     │
 638 │   defp handle_can_use_tool_request(request_id, request, state) do
     │        ~
     │
     └─ lib/claude_agent_sdk/client.ex:638:8: ClaudeAgentSDK.Client (module)

     warning: function encode_permission_response/3 is unused
     │
 713 │   defp encode_permission_response(request_id, :allow, result) do
     │        ~
     │
     └─ lib/claude_agent_sdk/client.ex:713:8: ClaudeAgentSDK.Client (module)

     warning: function encode_permission_error_response/2 is unused
     │
 739 │   defp encode_permission_error_response(request_id, error_message) do
     │        ~
     │
     └─ lib/claude_agent_sdk/client.ex:739:8: ClaudeAgentSDK.Client (module)

    warning: variable "block" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 98 │   defmacro deftool(name, description, input_schema, do: block) when is_atom(name) do
    │                                                         ~~~~~
    │
    └─ lib/claude_agent_sdk/tool.ex:98:57: ClaudeAgentSDK.Tool.deftool/4

Running ExUnit with seed: 892416, max_cases: 48

    warning: variable "request" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 87 │       request = %{
    │       ~~~~~~~
    │
    └─ test/claude_agent_sdk/client_permission_test.exs:87:7: ClaudeAgentSDK.ClientPermissionTest."test Client with permission callbacks Client invokes callback on can_use_tool control request"/1

     error: undefined variable "description" (context ClaudeAgentSDK.Tool)
     │
 119 │           Tool: #{unquote(description)}
     │           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
     │
     └─ lib/claude_agent_sdk/tool.ex:119: ClaudeAgentSDK.SDKMCPServerTest.CalculatorTools (module)

     error: undefined variable "description" (context ClaudeAgentSDK.Tool)
     │
 119 │           Tool: #{unquote(description)}
     │           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
     │
     └─ lib/claude_agent_sdk/tool.ex:119: ClaudeAgentSDK.ToolTest.TestTools (module)


== Compilation error in file test/claude_agent_sdk/sdk_mcp_server_test.exs ==
** (CompileError) test/claude_agent_sdk/sdk_mcp_server_test.exs: cannot compile module ClaudeAgentSDK.SDKMCPServerTest.CalculatorTools (errors have been logged)
    (claude_agent_sdk 0.3.0) expanding macro: ClaudeAgentSDK.Tool.deftool/4
home@Workstation:~/p/g/n/claude_agent_sdk$ mix test
Compiling 41 files (.ex)
Generated claude_agent_sdk app
Running ExUnit with seed: 586911, max_cases: 48

...................................................................................................................................

  1) test large payloads handles large input (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:132
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.LargeInputTool.Large.execute/1 is undefined or private
     code: {:ok, result} = LargeInputTool.Large.execute(%{"data" => large_string})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.LargeInputTool.Large.execute(%{"data" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" <> ...})
       test/claude_agent_sdk/tool/edge_cases_test.exs:152: (test)

............................

  2) test tool registration at compile time tools are discoverable (ClaudeAgentSDK.ToolTest)
     test/claude_agent_sdk/tool_test.exs:93
     Assertion with == failed
     code:  assert length(tools) == 3
     left:  0
     right: 3
     stacktrace:
       test/claude_agent_sdk/tool_test.exs:97: (test)

.

  3) test deftool macro handles successful execution (ClaudeAgentSDK.ToolTest)
     test/claude_agent_sdk/tool_test.exs:74
     ** (UndefinedFunctionError) function ClaudeAgentSDK.ToolTest.TestTools.Greet.execute/1 is undefined or private
     code: {:ok, result} = TestTools.Greet.execute(%{"name" => "Alice"})
     stacktrace:
       ClaudeAgentSDK.ToolTest.TestTools.Greet.execute(%{"name" => "Alice"})
       test/claude_agent_sdk/tool_test.exs:75: (test)

..

  4) test deftool macro handles error execution (ClaudeAgentSDK.ToolTest)
     test/claude_agent_sdk/tool_test.exs:79
     ** (UndefinedFunctionError) function ClaudeAgentSDK.ToolTest.TestTools.ErrorTool.execute/1 is undefined or private
     code: {:error, reason} = TestTools.ErrorTool.execute(%{})
     stacktrace:
       ClaudeAgentSDK.ToolTest.TestTools.ErrorTool.execute(%{})
       test/claude_agent_sdk/tool_test.exs:80: (test)

.

  5) test deftool macro generates execute function (ClaudeAgentSDK.ToolTest)
     test/claude_agent_sdk/tool_test.exs:67
     Expected truthy, got false
     code: assert function_exported?(TestTools.Add, :execute, 1)
     stacktrace:
       test/claude_agent_sdk/tool_test.exs:68: (test)



  6) test complex input schemas nested object schema (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:52
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.NestedTool.Nested.execute/1 is undefined or private
     code: NestedTool.Nested.execute(%{"user" => %{"name" => "Alice", "age" => 30}})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.NestedTool.Nested.execute(%{"user" => %{"age" => 30, "name" => "Alice"}})
       test/claude_agent_sdk/tool/edge_cases_test.exs:77: (test)

...

  7) test large payloads handles large output (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:157
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.LargeOutputTool.LargeOut.execute/1 is undefined or private
     code: {:ok, result} = LargeOutputTool.LargeOut.execute(%{})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.LargeOutputTool.LargeOut.execute(%{})
       test/claude_agent_sdk/tool/edge_cases_test.exs:171: (test)



  8) test complex input schemas array schema (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:82
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.ArrayTool.ArrayInput.execute/1 is undefined or private
     code: {:ok, result} = ArrayTool.ArrayInput.execute(%{"items" => ["a", "b", "c"]})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.ArrayTool.ArrayInput.execute(%{"items" => ["a", "b", "c"]})
       test/claude_agent_sdk/tool/edge_cases_test.exs:104: (test)

.
14:14:29.920 [error] Task #PID<0.850.0> started from #PID<0.843.0> terminating
** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute/1 is undefined or private
    ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute(%{"sleep_ms" => 10})
    (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
    (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4
Function: #Function<3.3585428/0 in ClaudeAgentSDK.Tool.EdgeCasesTest."test concurrent tool execution multiple tools execute concurrently without interference"/1>
    Args: []

14:14:29.920 [error] Task #PID<0.851.0> started from #PID<0.843.0> terminating
** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute/1 is undefined or private
    ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute(%{"sleep_ms" => 20})
    (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
    (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4
Function: #Function<3.3585428/0 in ClaudeAgentSDK.Tool.EdgeCasesTest."test concurrent tool execution multiple tools execute concurrently without interference"/1>
    Args: []



14:14:29.920 [error] Task #PID<0.852.0> started from #PID<0.843.0> terminating
** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute/1 is undefined or private
    ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute(%{"sleep_ms" => 30})
    (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
    (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4
Function: #Function<3.3585428/0 in ClaudeAgentSDK.Tool.EdgeCasesTest."test concurrent tool execution multiple tools execute concurrently without interference"/1>
    Args: []
  9) test concurrent tool execution multiple tools execute concurrently without interference (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:178
     ** (EXIT from #PID<0.843.0>) an exception was raised:
         ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute/1 is undefined or private
             ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute(%{"sleep_ms" => 10})
             (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
             (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4

    warning: ClaudeAgentSDK.ToolTest.TestTools.Add.execute/1 is undefined or private
    │
 70 │       {:ok, result} = TestTools.Add.execute(%{"a" => 5, "b" => 3})
    │                                     ~
    │
    └─ test/claude_agent_sdk/tool_test.exs:70:37: ClaudeAgentSDK.ToolTest."test deftool macro generates execute function"/1

    warning: ClaudeAgentSDK.ToolTest.TestTools.Greet.execute/1 is undefined or private
    │
 75 │       {:ok, result} = TestTools.Greet.execute(%{"name" => "Alice"})
    │                                       ~
    │
    └─ test/claude_agent_sdk/tool_test.exs:75:39: ClaudeAgentSDK.ToolTest."test deftool macro handles successful execution"/1

    warning: ClaudeAgentSDK.ToolTest.TestTools.ErrorTool.execute/1 is undefined or private
    │
 80 │       {:error, reason} = TestTools.ErrorTool.execute(%{})
    │                                              ~
    │
    └─ test/claude_agent_sdk/tool_test.exs:80:46: ClaudeAgentSDK.ToolTest."test deftool macro handles error execution"/1



 10) test error conditions gracefully handles malformed input (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:211
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.StrictTool.Strict.execute/1 is undefined or private
     code: assert {:error, msg} = StrictTool.Strict.execute(%{})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.StrictTool.Strict.execute(%{})
       test/claude_agent_sdk/tool/edge_cases_test.exs:235: (test)



 11) test empty tool definitions tool with no required fields (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:28
     ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.OptionalTool.Optional.execute/1 is undefined or private
     code: {:ok, result} = OptionalTool.Optional.execute(%{})
     stacktrace:
       ClaudeAgentSDK.Tool.EdgeCasesTest.OptionalTool.Optional.execute(%{})
       test/claude_agent_sdk/tool/edge_cases_test.exs:46: (test)


14:14:30.011 [error] Task #PID<0.879.0> started from #PID<0.872.0> terminating
** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout.execute/1 is undefined or private
    ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout.execute(%{})
    (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
    (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4
Function: #Function<2.3585428/0 in ClaudeAgentSDK.Tool.EdgeCasesTest."test error conditions handles tool execution timeout"/1>
    Args: []


 12) test error conditions handles tool execution timeout (ClaudeAgentSDK.Tool.EdgeCasesTest)
     test/claude_agent_sdk/tool/edge_cases_test.exs:246
     ** (EXIT from #PID<0.872.0>) an exception was raised:
         ** (UndefinedFunctionError) function ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout.execute/1 is undefined or private
             ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout.execute(%{})
             (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
             (elixir 1.18.4) lib/task/supervised.ex:36: Task.Supervised.reply/4

    warning: ClaudeAgentSDK.Tool.EdgeCasesTest.OptionalTool.Optional.execute/1 is undefined (module ClaudeAgentSDK.Tool.EdgeCasesTest.OptionalTool.Optional is not available or is yet to be defined)
    │
 46 │       {:ok, result} = OptionalTool.Optional.execute(%{})
    │                                             ~
    │
    └─ test/claude_agent_sdk/tool/edge_cases_test.exs:46:45: ClaudeAgentSDK.Tool.EdgeCasesTest."test empty tool definitions tool with no required fields"/1

    warning: ClaudeAgentSDK.Tool.EdgeCasesTest.NestedTool.Nested.execute/1 is undefined or private
    │
 77 │         NestedTool.Nested.execute(%{"user" => %{"name" => "Alice", "age" => 30}})
    │                           ~
    │
    └─ test/claude_agent_sdk/tool/edge_cases_test.exs:77:27: ClaudeAgentSDK.Tool.EdgeCasesTest."test complex input schemas nested object schema"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.ArrayTool.ArrayInput.execute/1 is undefined or private
     │
 104 │       {:ok, result} = ArrayTool.ArrayInput.execute(%{"items" => ["a", "b", "c"]})
     │                                            ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:104:44: ClaudeAgentSDK.Tool.EdgeCasesTest."test complex input schemas array schema"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.LargeInputTool.Large.execute/1 is undefined or private
     │
 152 │       {:ok, result} = LargeInputTool.Large.execute(%{"data" => large_string})
     │                                            ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:152:44: ClaudeAgentSDK.Tool.EdgeCasesTest."test large payloads handles large input"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.LargeOutputTool.LargeOut.execute/1 is undefined or private
     │
 171 │       {:ok, result} = LargeOutputTool.LargeOut.execute(%{})
     │                                                ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:171:48: ClaudeAgentSDK.Tool.EdgeCasesTest."test large payloads handles large output"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.ConcurrentTool.Concurrent.execute/1 is undefined or private
     │
 200 │             ConcurrentTool.Concurrent.execute(%{"sleep_ms" => i})
     │                                       ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:200:39: ClaudeAgentSDK.Tool.EdgeCasesTest."test concurrent tool execution multiple tools execute concurrently without interference"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.StrictTool.Strict.execute/1 is undefined or private
     │
 235 │       assert {:error, msg} = StrictTool.Strict.execute(%{})
     │                                                ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:235:48: ClaudeAgentSDK.Tool.EdgeCasesTest."test error conditions gracefully handles malformed input"/1
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:239:48: ClaudeAgentSDK.Tool.EdgeCasesTest."test error conditions gracefully handles malformed input"/1
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:243:43: ClaudeAgentSDK.Tool.EdgeCasesTest."test error conditions gracefully handles malformed input"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout.execute/1 is undefined (module ClaudeAgentSDK.Tool.EdgeCasesTest.TimeoutTool.Timeout is not available or is yet to be defined)
     │
 262 │       task = Task.async(fn -> TimeoutTool.Timeout.execute(%{}) end)
     │                                                   ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:262:51: ClaudeAgentSDK.Tool.EdgeCasesTest."test error conditions handles tool execution timeout"/1

     warning: ClaudeAgentSDK.Tool.EdgeCasesTest.SingleChar.A.__tool_metadata__/0 is undefined (module ClaudeAgentSDK.Tool.EdgeCasesTest.SingleChar.A is not available or is yet to be defined)
     │
 304 │       metadata = SingleChar.A.__tool_metadata__()
     │                               ~
     │
     └─ test/claude_agent_sdk/tool/edge_cases_test.exs:304:31: ClaudeAgentSDK.Tool.EdgeCasesTest."test tool naming edge cases handles single character names"/1

.............
14:14:30.028 [debug] Sent initialize request
.
14:14:30.028 [debug] Terminating client

14:14:30.029 [debug] Sent initialize request

14:14:30.029 [debug] Terminating client
...........................................*
14:14:30.082 [debug] Sent initialize request


 13) test set_agent/2 updates model when switching agents (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:137
     Assertion with == failed
     code:  assert initial_state.options.model == "claude-sonnet-4"
     left:  nil
     right: "claude-sonnet-4"
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:150: (test)


14:14:30.083 [debug] Sent initialize request


 14) test set_agent/2 updates allowed tools when switching agents (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:112
     Assertion with == failed
     code:  assert initial_state.options.allowed_tools == ["Read", "Write", "Bash"]
     left:  nil
     right: ["Read", "Write", "Bash"]
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:125: (test)


14:14:30.083 [debug] Sent initialize request

14:14:30.084 [debug] Terminating client
.
14:14:30.084 [debug] Sent initialize request
.
14:14:30.084 [debug] Terminating client

14:14:30.085 [debug] Sent initialize request

14:14:30.085 [debug] Sent initialize request

14:14:30.086 [debug] Sent initialize request

14:14:30.087 [debug] Sent initialize request

14:14:30.087 [debug] Terminating client

14:14:30.088 [debug] Sent initialize request

14:14:30.088 [debug] Terminating client

14:14:30.089 [debug] Sent initialize request

14:14:30.089 [debug] Terminating client

14:14:30.090 [debug] Sent initialize request

14:14:30.090 [debug] Terminating client

14:14:30.090 [debug] Sent initialize request

14:14:30.090 [debug] Terminating client

14:14:30.091 [debug] Sent initialize request

14:14:30.091 [debug] Sent initialize request

14:14:30.091 [debug] Terminating client

14:14:30.092 [debug] Sent initialize request

14:14:30.092 [debug] Terminating client

14:14:30.092 [debug] Sent initialize request

14:14:30.092 [debug] Terminating client

14:14:30.093 [debug] Sent initialize request

14:14:30.093 [debug] Terminating client

14:14:30.093 [debug] Sent initialize request

14:14:30.093 [debug] Terminating client

14:14:30.094 [debug] Sent initialize request

14:14:30.094 [debug] Terminating client


 15) test set_agent/2 switches to a different agent (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:43
     ** (KeyError) key :current_agent not found in: %{
       port: #Port<0.19>,
       buffer: "",
       registry: %ClaudeAgentSDK.Hooks.Registry{
         callbacks: %{},
         reverse_map: %{},
         counter: 0
       },
       options: %ClaudeAgentSDK.Options{
         max_turns: nil,
         system_prompt: nil,
         append_system_prompt: nil,
         output_format: nil,
         allowed_tools: nil,
         disallowed_tools: nil,
         mcp_config: nil,
         permission_prompt_tool: nil,
         permission_mode: nil,
         cwd: nil,
         verbose: nil,
         executable: nil,
         executable_args: nil,
         path_to_claude_code_executable: nil,
         abort_ref: nil,
         model: nil,
         fallback_model: nil,
         agents: %{
           writer: %ClaudeAgentSDK.Agent{
             name: nil,
             description: "Documentation expert",
             prompt: "You excel at writing clear documentation",
             allowed_tools: ["Read", "Write"],
             model: "claude-opus-4"
           },
           coder: %ClaudeAgentSDK.Agent{
             name: nil,
             description: "Code expert",
             prompt: "You are an expert programmer",
             allowed_tools: ["Read", "Write", "Bash"],
             model: "claude-sonnet-4"
           }
         },
         agent: :writer,
         session_id: nil,
         fork_session: nil,
         add_dir: nil,
         strict_mcp_config: nil,
         hooks: nil,
         can_use_tool: nil
       },
       initialized: false,
       session_id: nil,
       subscribers: [],
       pending_requests: %{}
     }
     code: assert state.current_agent == :writer
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:59: (test)


14:14:30.095 [debug] Sent initialize request



14:14:30.095 [debug] Terminating client
 16) test Agent validation on start_link fails to start when active agent not in agents map (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:336
     match (=) failed
     code:  assert {:error, {:agents_validation_failed, {:agent_not_found, :nonexistent}}} =
              Client.start_link(options)
     left:  {:error, {:agents_validation_failed, {:agent_not_found, :nonexistent}}}
     right: {:ok, #PID<0.975.0>}
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:342: (test)


14:14:30.095 [debug] Sent initialize request



14:14:30.095 [debug] Terminating client
 17) test set_agent/2 switches between multiple agents (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:162
     ** (KeyError) key :current_agent not found in: %{
       port: #Port<0.20>,
       buffer: "",
       registry: %ClaudeAgentSDK.Hooks.Registry{
         callbacks: %{},
         reverse_map: %{},
         counter: 0
       },
       options: %ClaudeAgentSDK.Options{
         max_turns: nil,
         system_prompt: nil,
         append_system_prompt: nil,
         output_format: nil,
         allowed_tools: nil,
         disallowed_tools: nil,
         mcp_config: nil,
         permission_prompt_tool: nil,
         permission_mode: nil,
         cwd: nil,
         verbose: nil,
         executable: nil,
         executable_args: nil,
         path_to_claude_code_executable: nil,
         abort_ref: nil,
         model: nil,
         fallback_model: nil,
         agents: %{
           writer: %ClaudeAgentSDK.Agent{
             name: nil,
             description: "Documentation expert",
             prompt: "You excel at writing clear documentation",
             allowed_tools: ["Read", "Write"],
             model: "claude-opus-4"
           },
           coder: %ClaudeAgentSDK.Agent{
             name: nil,
             description: "Code expert",
             prompt: "You are an expert programmer",
             allowed_tools: ["Read", "Write", "Bash"],
             model: "claude-sonnet-4"
           },
           researcher: %ClaudeAgentSDK.Agent{
             name: nil,
             description: "Research specialist",
             prompt: "You are skilled at research and analysis",
             allowed_tools: ["WebSearch", "WebFetch"],
             model: "claude-sonnet-4"
           }
         },
         agent: :writer,
         session_id: nil,
         fork_session: nil,
         add_dir: nil,
         strict_mcp_config: nil,
         hooks: nil,
         can_use_tool: nil
       },
       initialized: false,
       session_id: nil,
       subscribers: [],
       pending_requests: %{}
     }
     code: assert state1.current_agent == :writer
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:181: (test)



 18) test set_agent/2 updates system prompt when switching agents (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:87
     Assertion with == failed
     code:  assert initial_state.options.system_prompt == code_agent.prompt
     left:  nil
     right: "You are an expert programmer"
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:100: (test)




14:14:30.096 [debug] Sent initialize request
 19) test Agent validation on start_link fails to start with invalid agent configuration (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:322
     match (=) failed
     code:  assert {:error, {:agents_validation_failed, _reason}} = Client.start_link(options)
     left:  {:error, {:agents_validation_failed, _reason}}
     right: {:ok, #PID<0.981.0>}
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:333: (test)


14:14:30.096 [debug] Terminating client
.....

 20) test set_agent/2 returns error when getting agent with no agents configured (ClaudeAgentSDK.ClientAgentsTest)
     test/claude_agent_sdk/client_agents_test.exs:248
     match (=) failed
     code:  assert {:error, :no_agents_configured} = Client.get_agent(client)
     left:  {:error, :no_agents_configured}
     right: {:error, :no_agent_configured}
     stacktrace:
       test/claude_agent_sdk/client_agents_test.exs:253: (test)

.*........
14:14:30.096 [debug] Sent initialize request

14:14:30.096 [debug] Terminating client
.
14:14:30.097 [debug] Sent initialize request
.
14:14:30.097 [debug] Terminating client

14:14:30.098 [debug] Sent initialize request

14:14:30.098 [debug] Terminating client
.
14:14:30.099 [debug] Sent initialize request
.
14:14:30.099 [debug] Terminating client

14:14:30.099 [debug] Sent initialize request
.
14:14:30.100 [debug] Terminating client

14:14:30.101 [debug] Sent initialize request
.
14:14:30.101 [debug] Terminating client

14:14:30.103 [debug] Sent initialize request
.
14:14:30.103 [debug] Terminating client

14:14:30.104 [debug] Sent initialize request
.
14:14:30.105 [debug] Terminating client

14:14:30.108 [debug] Sent initialize request
.
14:14:30.108 [debug] Terminating client

14:14:30.111 [debug] Sent initialize request
.
14:14:30.111 [debug] Terminating client
.
14:14:30.114 [debug] Sent initialize request
.
14:14:30.114 [debug] Terminating client

14:14:30.118 [debug] Sent initialize request
.
14:14:30.118 [debug] Terminating client
..............*
14:14:30.177 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.178 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.178 [info] AuthManager: No stored token found, will authenticate on demand

14:14:30.203 [info] AuthManager: Loaded existing token from storage
.
14:14:30.203 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.204 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.204 [info] AuthManager: No stored token found, will authenticate on demand

14:14:30.204 [info] AuthManager: Loaded existing token from storage
.
14:14:30.204 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.204 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.205 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.205 [info] AuthManager: No stored token found, will authenticate on demand

14:14:30.205 [info] AuthManager: Loaded existing token from storage
.
14:14:30.205 [info] AuthManager: No stored token found, will authenticate on demand
.
14:14:30.205 [info] AuthManager: No stored token found, will authenticate on demand

14:14:30.205 [info] AuthManager: Loaded existing token from storage
.
14:14:30.206 [info] AuthManager: No stored token found, will authenticate on demand

14:14:30.206 [info] AuthManager: Loaded existing token from storage
.*****************....

 21) test SDK MCP server in Options accepts mix of SDK and external servers (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:115
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     code: ClaudeAgentSDK.create_sdk_mcp_server(
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:117: (test)



 22) test SDK MCP server in Options accepts SDK server in mcp_servers option (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:100
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     code: ClaudeAgentSDK.create_sdk_mcp_server(
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:102: (test)

...
14:14:30.234 [error] Tool execution error: %UndefinedFunctionError{module: ClaudeAgentSDK.SDKMCPServerTest.ErrorTools.RaiseTool, function: :execute, arity: 1, reason: nil, message: nil}



14:14:30.234 [error] Tool execution error: %UndefinedFunctionError{module: ClaudeAgentSDK.SDKMCPServerTest.ErrorTools.FailTool, function: :execute, arity: 1, reason: nil, message: nil}
 23) test server lifecycle multiple servers can coexist (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:296
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     code: ClaudeAgentSDK.create_sdk_mcp_server(
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:298: (test)


14:14:30.235 [error] Tool execution error: %UndefinedFunctionError{module: ClaudeAgentSDK.SDKMCPServerTest.ImageTools.GenerateChart, function: :execute, arity: 1, reason: nil, message: nil}


 24) test tool execution through server executes tool successfully (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:153
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:144: ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_setup_2_0/1
       ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_describe_2/1

.

 25) test server lifecycle server registry is supervised (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:280
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     code: ClaudeAgentSDK.create_sdk_mcp_server(
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:282: (test)



 26) test tool execution through server executes different tools (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:159
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:144: ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_setup_2_0/1
       ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_describe_2/1



 27) test tool execution through server handles tool not found (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:166
     ** (ArgumentError) CalculatorTools.Add is not a valid tool module (missing __tool_metadata__/0)
     stacktrace:
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:186: anonymous fn/3 in ClaudeAgentSDK.create_sdk_mcp_server/1
       (elixir 1.18.4) lib/enum.ex:2546: Enum."-reduce/3-lists^foldl/2-0-"/3
       (claude_agent_sdk 0.3.0) lib/claude_agent_sdk.ex:181: ClaudeAgentSDK.create_sdk_mcp_server/1
       test/claude_agent_sdk/sdk_mcp_server_test.exs:144: ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_setup_2_0/1
       ClaudeAgentSDK.SDKMCPServerTest.__ex_unit_describe_2/1

.

 28) test error handling handles tool errors gracefully (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:193
     match (=) failed
     code:  assert {:error, "Expected error"} = Tool.Registry.execute_tool(server.registry_pid, :fail_tool, %{})
     left:  {:error, "Expected error"}
     right: {
              :error,
              %{
                "content" => [%{"text" => "Error executing tool: function ClaudeAgentSDK.SDKMCPServerTest.ErrorTools.FailTool.execute/1 is undefined or private", "type" => "text"}],
                "isError" => true
              }
            }
     stacktrace:
       test/claude_agent_sdk/sdk_mcp_server_test.exs:201: (test)



 29) test image content support returns image content correctly (ClaudeAgentSDK.SDKMCPServerTest)
     test/claude_agent_sdk/sdk_mcp_server_test.exs:256
     ** (MatchError) no match of right hand side value: {:error, %{"content" => [%{"text" => "Error executing tool: function ClaudeAgentSDK.SDKMCPServerTest.ImageTools.GenerateChart.execute/1 is undefined or private", "type" => "text"}], "isError" => true}}
     code: {:ok, result} =
     stacktrace:
       test/claude_agent_sdk/sdk_mcp_server_test.exs:264: (test)

**********.......................................................................
Finished in 0.6 seconds (0.3s async, 0.2s sync)
419 tests, 29 failures, 30 skipped
