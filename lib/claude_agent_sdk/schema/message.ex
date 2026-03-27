defmodule ClaudeAgentSDK.Schema.Message do
  @moduledoc false

  alias ClaudeAgentSDK.Schema
  alias ClaudeAgentSDK.Schema.Options, as: OptionSchema
  alias CliSubprocessCore.Schema.Conventions

  @message_type_schema Zoi.map(
                         %{
                           "type" => Conventions.trimmed_string() |> Zoi.min(1)
                         },
                         unrecognized_keys: :preserve
                       )

  @assistant_schema Zoi.map(
                      %{
                        "type" => Conventions.trimmed_string() |> Zoi.min(1),
                        "message" => OptionSchema.any_json_map(),
                        "session_id" => Conventions.optional_trimmed_string(),
                        "parent_tool_use_id" => Conventions.optional_trimmed_string(),
                        "error" => Conventions.optional_trimmed_string()
                      },
                      unrecognized_keys: :preserve
                    )

  @user_schema Zoi.map(
                 %{
                   "type" => Conventions.trimmed_string() |> Zoi.min(1),
                   "message" => OptionSchema.any_json_map(),
                   "session_id" => Conventions.optional_trimmed_string(),
                   "parent_tool_use_id" => Conventions.optional_trimmed_string(),
                   "tool_use_result" => Conventions.optional_any(),
                   "uuid" => Conventions.optional_trimmed_string()
                 },
                 unrecognized_keys: :preserve
               )

  @result_schema Zoi.map(
                   %{
                     "type" => Conventions.trimmed_string() |> Zoi.min(1),
                     "subtype" => Conventions.optional_trimmed_string(),
                     "session_id" => Conventions.optional_trimmed_string(),
                     "result" => Conventions.optional_any(),
                     "structured_output" => Conventions.optional_any(),
                     "usage" => Conventions.optional_map(),
                     "total_cost_usd" => Conventions.optional_any(),
                     "duration_ms" => Conventions.optional_any(),
                     "duration_api_ms" => Conventions.optional_any(),
                     "num_turns" => Conventions.optional_any(),
                     "is_error" => Conventions.optional_any(),
                     "stop_reason" => Conventions.optional_any(),
                     "error" => Conventions.optional_trimmed_string()
                   },
                   unrecognized_keys: :preserve
                 )

  @system_schema Zoi.map(
                   %{
                     "type" => Conventions.trimmed_string() |> Zoi.min(1),
                     "subtype" => Conventions.optional_trimmed_string()
                   },
                   unrecognized_keys: :preserve
                 )

  @stream_event_schema Zoi.map(
                         %{
                           "type" => Conventions.trimmed_string() |> Zoi.min(1),
                           "uuid" => Conventions.optional_trimmed_string(),
                           "session_id" => Conventions.optional_trimmed_string(),
                           "parent_tool_use_id" => Conventions.optional_trimmed_string(),
                           "event" => OptionSchema.any_json_map()
                         },
                         unrecognized_keys: :preserve
                       )

  @rate_limit_info_schema Zoi.map(
                            %{
                              "status" => Conventions.trimmed_string() |> Zoi.min(1),
                              "resetsAt" => Conventions.optional_any(),
                              "rateLimitType" => Conventions.optional_trimmed_string(),
                              "utilization" => Conventions.optional_any(),
                              "isUsingOverage" => Conventions.optional_any(),
                              "overageStatus" => Conventions.optional_trimmed_string(),
                              "overageResetsAt" => Conventions.optional_any(),
                              "overageDisabledReason" => Conventions.optional_trimmed_string()
                            },
                            unrecognized_keys: :preserve
                          )

  @rate_limit_event_schema Zoi.map(
                             %{
                               "type" => Conventions.trimmed_string() |> Zoi.min(1),
                               "rate_limit_info" => @rate_limit_info_schema,
                               "uuid" => Conventions.trimmed_string() |> Zoi.min(1),
                               "session_id" => Conventions.trimmed_string() |> Zoi.min(1)
                             },
                             unrecognized_keys: :preserve
                           )

  @message_start_schema Zoi.map(
                          %{
                            "type" => Conventions.trimmed_string() |> Zoi.min(1),
                            "message" =>
                              Zoi.map(
                                %{
                                  "model" => Conventions.optional_trimmed_string(),
                                  "role" => Conventions.optional_trimmed_string(),
                                  "usage" => Conventions.optional_any()
                                },
                                unrecognized_keys: :preserve
                              )
                          },
                          unrecognized_keys: :preserve
                        )

  @content_block_start_schema Zoi.map(
                                %{
                                  "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                  "content_block" =>
                                    Zoi.map(
                                      %{
                                        "type" => Conventions.optional_trimmed_string(),
                                        "name" => Conventions.optional_trimmed_string(),
                                        "id" => Conventions.optional_trimmed_string(),
                                        "input" => Conventions.optional_any(),
                                        "thinking" => Conventions.optional_any(),
                                        "signature" => Conventions.optional_trimmed_string()
                                      },
                                      unrecognized_keys: :preserve
                                    )
                                },
                                unrecognized_keys: :preserve
                              )

  @content_block_delta_schema Zoi.map(
                                %{
                                  "type" => Conventions.trimmed_string() |> Zoi.min(1),
                                  "delta" =>
                                    Zoi.map(
                                      %{
                                        "type" => Conventions.optional_trimmed_string(),
                                        "text" => Conventions.optional_any(),
                                        "partial_json" => Conventions.optional_any(),
                                        "thinking" => Conventions.optional_any()
                                      },
                                      unrecognized_keys: :preserve
                                    )
                                },
                                unrecognized_keys: :preserve
                              )

  @content_block_stop_schema Zoi.map(
                               %{
                                 "type" => Conventions.trimmed_string() |> Zoi.min(1)
                               },
                               unrecognized_keys: :preserve
                             )

  @message_delta_schema Zoi.map(
                          %{
                            "type" => Conventions.trimmed_string() |> Zoi.min(1),
                            "delta" =>
                              Zoi.map(
                                %{
                                  "stop_reason" => Conventions.optional_trimmed_string(),
                                  "stop_sequence" => Conventions.optional_any()
                                },
                                unrecognized_keys: :preserve
                              )
                          },
                          unrecognized_keys: :preserve
                        )

  @message_stop_schema Zoi.map(
                         %{
                           "type" => Conventions.trimmed_string() |> Zoi.min(1),
                           "structured_output" => Conventions.optional_any(),
                           "error" => Conventions.optional_trimmed_string(),
                           "message" =>
                             Zoi.optional(
                               Zoi.nullish(
                                 Zoi.map(
                                   %{
                                     "structured_output" => Conventions.optional_any(),
                                     "error" => Conventions.optional_trimmed_string()
                                   },
                                   unrecognized_keys: :preserve
                                 )
                               )
                             )
                         },
                         unrecognized_keys: :preserve
                       )

  @stream_error_schema Zoi.map(
                         %{
                           "type" => Conventions.trimmed_string() |> Zoi.min(1),
                           "error" =>
                             Zoi.optional(
                               Zoi.nullish(
                                 Zoi.map(
                                   %{
                                     "type" => Conventions.optional_trimmed_string(),
                                     "message" => Conventions.optional_trimmed_string()
                                   },
                                   unrecognized_keys: :preserve
                                 )
                               )
                             )
                         },
                         unrecognized_keys: :preserve
                       )

  @spec parse(map()) ::
          {:ok, map()}
          | {:error, {:invalid_message_frame, CliSubprocessCore.Schema.error_detail()}}
  def parse(map) when is_map(map) do
    with {:ok, base} <- Schema.parse(@message_type_schema, map, :invalid_message_frame) do
      parse_message_family(Map.get(base, "type"), map)
    end
  end

  @spec parse_stream_event(map()) ::
          {:ok, map()}
          | {:error, {:invalid_stream_event, CliSubprocessCore.Schema.error_detail()}}
  def parse_stream_event(map) when is_map(map) do
    with {:ok, base} <- Schema.parse(@message_type_schema, map, :invalid_stream_event) do
      parse_stream_family(Map.get(base, "type"), map)
    end
  end

  defp parse_message_family("assistant", map),
    do: Schema.parse(@assistant_schema, map, :invalid_message_frame)

  defp parse_message_family("user", map),
    do: Schema.parse(@user_schema, map, :invalid_message_frame)

  defp parse_message_family("result", map),
    do: Schema.parse(@result_schema, map, :invalid_message_frame)

  defp parse_message_family("system", map),
    do: Schema.parse(@system_schema, map, :invalid_message_frame)

  defp parse_message_family("stream_event", map),
    do: Schema.parse(@stream_event_schema, map, :invalid_message_frame)

  defp parse_message_family("rate_limit_event", map),
    do: Schema.parse(@rate_limit_event_schema, map, :invalid_message_frame)

  defp parse_message_family(_other, map), do: {:ok, map}

  defp parse_stream_family("message_start", map),
    do: Schema.parse(@message_start_schema, map, :invalid_stream_event)

  defp parse_stream_family("content_block_start", map),
    do: Schema.parse(@content_block_start_schema, map, :invalid_stream_event)

  defp parse_stream_family("content_block_delta", map),
    do: Schema.parse(@content_block_delta_schema, map, :invalid_stream_event)

  defp parse_stream_family("content_block_stop", map),
    do: Schema.parse(@content_block_stop_schema, map, :invalid_stream_event)

  defp parse_stream_family("message_delta", map),
    do: Schema.parse(@message_delta_schema, map, :invalid_stream_event)

  defp parse_stream_family("message_stop", map),
    do: Schema.parse(@message_stop_schema, map, :invalid_stream_event)

  defp parse_stream_family("error", map),
    do: Schema.parse(@stream_error_schema, map, :invalid_stream_event)

  defp parse_stream_family(_other, map), do: {:ok, map}
end
