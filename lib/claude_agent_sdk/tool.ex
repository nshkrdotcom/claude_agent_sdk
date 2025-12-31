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
  - Optional: `"is_error"` - Boolean indicating error state
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

  @doc """
  Creates a simple JSON Schema for common tool patterns.

  This helper reduces boilerplate when defining tools with straightforward
  input requirements. It supports several input formats for flexibility.

  ## Input Formats

  ### List of atoms (all string, all required)

      simple_schema([:name, :path])
      # => %{type: "object", properties: %{name: %{type: "string"}, path: %{type: "string"}}, required: ["name", "path"]}

  ### Keyword list with types

      simple_schema(name: :string, count: :number, enabled: :boolean)
      # => %{type: "object", properties: %{...}, required: ["name", "count", "enabled"]}

  ### Keyword list with descriptions

      simple_schema(name: {:string, "User's full name"}, age: {:number, "Age in years"})
      # => Adds description field to each property

  ### Optional fields

      simple_schema(name: :string, email: {:string, optional: true})
      # => "name" is required, "email" is not

  ## Supported Types

  - `:string` - String type
  - `:number` - Number type (float or int)
  - `:integer` - Integer type
  - `:boolean` - Boolean type
  - `:array` - Array type
  - `:object` - Object type

  ## Examples

      # Simple tool with two required string fields
      deftool :create_file, "Create a file", Tool.simple_schema([:path, :content]) do
        def execute(%{"path" => path, "content" => content}) do
          File.write!(path, content)
          {:ok, %{"content" => [%{"type" => "text", "text" => "Created \#{path}"}]}}
        end
      end

      # Tool with mixed types
      deftool :search, "Search files",
        Tool.simple_schema(query: :string, max_results: {:integer, optional: true}) do
        def execute(%{"query" => query} = args) do
          max = Map.get(args, "max_results", 10)
          # ... search logic
        end
      end
  """
  @spec simple_schema(keyword() | [atom()]) :: map()
  def simple_schema(fields) when is_list(fields) do
    {properties, required} = build_schema_fields(fields)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  defp build_schema_fields([]), do: {%{}, []}

  # List of atoms - all string, all required
  defp build_schema_fields([first | _] = fields) when is_atom(first) do
    properties =
      fields
      |> Enum.map(fn name -> {name, %{type: "string"}} end)
      |> Map.new()

    required = Enum.map(fields, &to_string/1)

    {properties, required}
  end

  # Keyword list
  defp build_schema_fields(fields) do
    Enum.reduce(fields, {%{}, []}, fn {name, spec}, {props, req} ->
      {prop, is_required} = parse_field_spec(spec)
      new_props = Map.put(props, name, prop)
      new_req = if is_required, do: [to_string(name) | req], else: req
      {new_props, new_req}
    end)
    |> then(fn {props, req} -> {props, Enum.reverse(req)} end)
  end

  # Type atom only
  defp parse_field_spec(type) when is_atom(type) do
    {%{type: type_to_string(type)}, true}
  end

  # Type with description
  defp parse_field_spec({type, description}) when is_atom(type) and is_binary(description) do
    {%{type: type_to_string(type), description: description}, true}
  end

  # Type with options keyword list
  defp parse_field_spec({type, opts}) when is_atom(type) and is_list(opts) do
    is_optional = Keyword.get(opts, :optional, false)
    description = Keyword.get(opts, :description)

    prop =
      %{type: type_to_string(type)}
      |> maybe_add_description(description)

    {prop, not is_optional}
  end

  defp maybe_add_description(prop, nil), do: prop
  defp maybe_add_description(prop, desc), do: Map.put(prop, :description, desc)

  defp type_to_string(:string), do: "string"
  defp type_to_string(:number), do: "number"
  defp type_to_string(:integer), do: "integer"
  defp type_to_string(:boolean), do: "boolean"
  defp type_to_string(:array), do: "array"
  defp type_to_string(:object), do: "object"
  defp type_to_string(other), do: to_string(other)
end
