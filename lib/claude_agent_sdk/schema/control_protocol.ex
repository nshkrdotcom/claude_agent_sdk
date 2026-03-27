defmodule ClaudeAgentSDK.Schema.ControlProtocol do
  @moduledoc false

  alias ClaudeAgentSDK.Schema
  alias ClaudeAgentSDK.Schema.Message, as: MessageSchema
  alias ClaudeAgentSDK.Schema.Options, as: OptionSchema
  alias CliSubprocessCore.Schema.Conventions

  @message_type_schema Zoi.map(
                         %{
                           "type" => Conventions.trimmed_string() |> Zoi.min(1)
                         },
                         unrecognized_keys: :preserve
                       )

  @control_request_schema Zoi.map(
                            %{
                              "type" => Conventions.trimmed_string() |> Zoi.min(1),
                              "request_id" => Conventions.trimmed_string() |> Zoi.min(1),
                              "request" =>
                                Zoi.map(
                                  %{
                                    "subtype" => Conventions.optional_trimmed_string(),
                                    "hooks" => OptionSchema.initialize_hooks(),
                                    "sdkMcpServers" => OptionSchema.sdk_mcp_servers(),
                                    "agents" => OptionSchema.agents_registry()
                                  },
                                  unrecognized_keys: :preserve
                                )
                            },
                            unrecognized_keys: :preserve
                          )

  @control_response_schema Zoi.map(
                             %{
                               "type" => Conventions.trimmed_string() |> Zoi.min(1),
                               "response" =>
                                 Zoi.map(
                                   %{
                                     "subtype" => Conventions.optional_trimmed_string(),
                                     "request_id" => Conventions.optional_trimmed_string(),
                                     "response" => OptionSchema.optional_json_map(),
                                     "error" => Conventions.optional_trimmed_string()
                                   },
                                   unrecognized_keys: :preserve
                                 )
                             },
                             unrecognized_keys: :preserve
                           )

  @control_cancel_request_schema Zoi.map(
                                   %{
                                     "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                     "request_id" => Conventions.optional_trimmed_string(),
                                     "request" => OptionSchema.optional_json_map()
                                   },
                                   unrecognized_keys: :preserve
                                 )

  @initialize_request_schema Zoi.map(
                               %{
                                 "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                 "request_id" => Conventions.trimmed_string() |> Zoi.min(1),
                                 "request" =>
                                   Zoi.map(
                                     %{
                                       "subtype" => Conventions.trimmed_string() |> Zoi.min(1),
                                       "hooks" => OptionSchema.initialize_hooks(),
                                       "sdkMcpServers" => OptionSchema.sdk_mcp_servers(),
                                       "agents" => OptionSchema.agents_registry()
                                     },
                                     unrecognized_keys: :preserve
                                   )
                               },
                               unrecognized_keys: :preserve
                             )

  @hook_success_response_schema Zoi.map(
                                  %{
                                    "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                    "response" =>
                                      Zoi.map(
                                        %{
                                          "subtype" => Conventions.trimmed_string() |> Zoi.min(1),
                                          "request_id" =>
                                            Conventions.trimmed_string() |> Zoi.min(1),
                                          "response" => OptionSchema.any_json_map()
                                        },
                                        unrecognized_keys: :preserve
                                      )
                                  },
                                  unrecognized_keys: :preserve
                                )

  @hook_error_response_schema Zoi.map(
                                %{
                                  "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                  "response" =>
                                    Zoi.map(
                                      %{
                                        "subtype" => Conventions.trimmed_string() |> Zoi.min(1),
                                        "request_id" =>
                                          Conventions.trimmed_string() |> Zoi.min(1),
                                        "error" => Conventions.trimmed_string() |> Zoi.min(1)
                                      },
                                      unrecognized_keys: :preserve
                                    )
                                },
                                unrecognized_keys: :preserve
                              )

  @spec parse_message(map()) ::
          {:ok, map()}
          | {:error, {:invalid_control_protocol_message, CliSubprocessCore.Schema.error_detail()}}
  def parse_message(map) when is_map(map) do
    with {:ok, base} <- Schema.parse(@message_type_schema, map, :invalid_control_protocol_message) do
      parse_family(Map.get(base, "type"), map)
    end
  end

  @spec validate_initialize_request!(map()) :: map()
  def validate_initialize_request!(request) when is_map(request) do
    Schema.parse!(@initialize_request_schema, request, :invalid_control_protocol_message)
  end

  @spec validate_hook_response!(map()) :: map()
  def validate_hook_response!(response) when is_map(response) do
    case get_in(response, ["response", "subtype"]) do
      "success" ->
        Schema.parse!(@hook_success_response_schema, response, :invalid_control_protocol_message)

      "error" ->
        Schema.parse!(@hook_error_response_schema, response, :invalid_control_protocol_message)

      _other ->
        Schema.parse!(@control_response_schema, response, :invalid_control_protocol_message)
    end
  end

  defp parse_family("control_request", map),
    do: Schema.parse(@control_request_schema, map, :invalid_control_protocol_message)

  defp parse_family("control_response", map),
    do: Schema.parse(@control_response_schema, map, :invalid_control_protocol_message)

  defp parse_family("control_cancel_request", map),
    do: Schema.parse(@control_cancel_request_schema, map, :invalid_control_protocol_message)

  defp parse_family("stream_event", map) do
    case MessageSchema.parse(map) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, {:invalid_message_frame, details}} ->
        {:error, {:invalid_control_protocol_message, details}}
    end
  end

  defp parse_family(_other, map), do: {:ok, map}
end
