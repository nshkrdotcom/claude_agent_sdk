defmodule ClaudeAgentSDK.Schema.Options do
  @moduledoc """
  Reusable Claude option schemas for JSON object registries and structured
  output payloads.
  """

  alias CliSubprocessCore.Schema.Conventions

  @spec any_json_map() :: Zoi.schema()
  def any_json_map, do: Zoi.map(%{}, unrecognized_keys: :preserve)

  @spec optional_json_map() :: Zoi.schema()
  def optional_json_map, do: Zoi.optional(Zoi.nullish(any_json_map()))

  @spec json_object_registry() :: Zoi.schema()
  def json_object_registry do
    Zoi.optional(
      Zoi.nullish(
        Zoi.map(
          Conventions.trimmed_string() |> Zoi.min(1),
          any_json_map(),
          []
        )
      )
    )
  end

  @spec initialize_hooks() :: Zoi.schema()
  def initialize_hooks, do: optional_json_map()

  @spec sdk_mcp_servers() :: Zoi.schema()
  def sdk_mcp_servers, do: json_object_registry()

  @spec agents_registry() :: Zoi.schema()
  def agents_registry, do: json_object_registry()

  @spec structured_output_format() :: Zoi.schema()
  def structured_output_format do
    Zoi.map(
      %{
        "type" => Conventions.trimmed_string() |> Zoi.min(1),
        "schema" => any_json_map()
      },
      unrecognized_keys: :preserve
    )
  end
end
