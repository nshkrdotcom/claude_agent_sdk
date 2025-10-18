defmodule ClaudeAgentSDK.Tool do
  @moduledoc """
  Tool definition macro for creating in-process MCP tools.

  Provides the `deftool` macro for defining tools that can be used with
  `create_sdk_mcp_server/2` to create SDK-based MCP servers without subprocess overhead.

  ## Usage

      defmodule MyTools do
        use ClaudeAgentSDK.Tool

        deftool :calculator,
                "Performs basic calculations",
                %{
                  type: "object",
                  properties: %{
                    expression: %{type: "string"}
                  },
                  required: ["expression"]
                } do
          def execute(%{"expression" => expr}) do
            result = eval_expression(expr)
            {:ok, %{"content" => [%{"type" => "text", "text" => "Result: \#{result}"}]}}
          end

          defp eval_expression(expr) do
            # Implementation
          end
        end
      end

  ## Tool Metadata

  Each tool defined with `deftool` creates a module with:
  - `__tool_metadata__/0` - Returns tool metadata
  - `execute/1` - Executes the tool with given input

  ## Input/Output Format

  Tools receive input as a map matching the input_schema and return:
  - `{:ok, result}` - Success with result map
  - `{:error, reason}` - Error with reason string

  Result map should contain:
  - `"content"` - List of content blocks (text, image, etc.)
  - Optional: `"isError"` - Boolean indicating error state
  """

  @doc """
  When used, defines the `deftool` macro in the calling module.
  """
  defmacro __using__(_opts) do
    quote do
      import ClaudeAgentSDK.Tool, only: [deftool: 3, deftool: 4]

      Module.register_attribute(__MODULE__, :tools, accumulate: true)

      @before_compile ClaudeAgentSDK.Tool
    end
  end

  @doc """
  Collects all defined tools and makes them discoverable.
  """
  defmacro __before_compile__(env) do
    tools = Module.get_attribute(env.module, :tools)

    quote do
      def __tools__ do
        unquote(Macro.escape(tools))
      end
    end
  end

  @doc """
  Defines a tool with name, description, and input schema.

  ## Parameters

  - `name` - Atom tool name (e.g., `:calculator`)
  - `description` - String description of what the tool does
  - `input_schema` - JSON Schema map defining expected input
  - `do_block` - Block containing `execute/1` function definition

  ## Examples

      deftool :add, "Add two numbers", %{
        type: "object",
        properties: %{a: %{type: "number"}, b: %{type: "number"}},
        required: ["a", "b"]
      } do
        def execute(%{"a" => a, "b" => b}) do
          {:ok, %{"content" => [%{"type" => "text", "text" => "Result: \#{a + b}"}]}}
        end
      end
  """
  defmacro deftool(name, description, input_schema, do: block) when is_atom(name) do
    # Generate module name from tool name (e.g., :my_tool -> MyTool)
    module_name = name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()

    quote location: :keep do
      # Register tool metadata for discovery BEFORE defining the module
      Module.put_attribute(__MODULE__, :tools, %{
        name: unquote(name),
        description: unquote(description),
        input_schema: unquote(input_schema),
        module: Module.concat(__MODULE__, unquote(module_name))
      })

      # Define the nested tool module using defmodule
      defmodule Module.concat(__MODULE__, unquote(module_name)) do
        @moduledoc """
        Tool: #{unquote(description)}

        ## Input Schema

        ```elixir
        #{inspect(unquote(input_schema), pretty: true)}
        ```
        """

        @tool_name unquote(name)
        @tool_description unquote(description)
        @tool_input_schema unquote(input_schema)

        @doc """
        Returns metadata about this tool.
        """
        def __tool_metadata__ do
          %{
            name: @tool_name,
            description: @tool_description,
            input_schema: @tool_input_schema,
            module: __MODULE__
          }
        end

        # Inject the execute function from the do block
        unquote(block)
      end
    end
  end

  @doc """
  Shorthand for deftool with minimal schema (just type: object).
  """
  defmacro deftool(name, description, do: block) do
    quote do
      deftool(unquote(name), unquote(description), %{type: "object"}, do: unquote(block))
    end
  end

  @doc """
  Lists all tools defined in a module.

  ## Parameters

  - `module` - The module that used `ClaudeAgentSDK.Tool`

  ## Returns

  List of tool metadata maps.

  ## Examples

      iex> ClaudeAgentSDK.Tool.list_tools(MyTools)
      [%{name: :calculator, description: "Performs calculations", ...}]
  """
  @spec list_tools(module()) :: [map()]
  def list_tools(module) do
    if function_exported?(module, :__tools__, 0) do
      module.__tools__()
    else
      []
    end
  end

  @doc """
  Validates a JSON schema map.

  ## Parameters

  - `schema` - JSON Schema map

  ## Returns

  Boolean indicating if schema is valid.

  ## Examples

      iex> ClaudeAgentSDK.Tool.valid_schema?(%{type: "object"})
      true

      iex> ClaudeAgentSDK.Tool.valid_schema?(%{})
      false
  """
  @spec valid_schema?(map()) :: boolean()
  def valid_schema?(schema) when is_map(schema) do
    # Basic validation: must have a type field
    Map.has_key?(schema, :type) or Map.has_key?(schema, "type")
  end

  def valid_schema?(_), do: false
end
