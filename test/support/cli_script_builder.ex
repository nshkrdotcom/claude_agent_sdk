defmodule ClaudeAgentSDK.TestSupport.CLIScriptBuilder do
  @moduledoc """
  Builder for creating complex CLI interaction scripts for testing.

  Provides a fluent API for constructing realistic streaming scenarios
  that interleave text deltas, tool calls, hooks, and control protocol messages.

  ## Examples

      # Simple text streaming
      script = CLIScriptBuilder.new()
        |> CLIScriptBuilder.emit_message_start()
        |> CLIScriptBuilder.emit_text("Hello ")
        |> CLIScriptBuilder.emit_text("World")
        |> CLIScriptBuilder.emit_message_stop()
        |> CLIScriptBuilder.build()

      # Text + Tool execution
      script = CLIScriptBuilder.new()
        |> CLIScriptBuilder.emit_message_start()
        |> CLIScriptBuilder.emit_text("Running command: ")
        |> CLIScriptBuilder.emit_tool_use("Bash", ~s({"command": "ls"}))
        |> CLIScriptBuilder.emit_text("Command complete")
        |> CLIScriptBuilder.emit_message_stop()
        |> CLIScriptBuilder.build()
  """

  alias ClaudeAgentSDK.TestSupport.MockCLI

  defstruct steps: [], current_block_index: 0

  @type t :: %__MODULE__{
          steps: [step()],
          current_block_index: integer()
        }

  @type step ::
          {:emit, map()}
          | {:delay, integer()}
          | {:wait_for_request}

  ## Builder API

  @doc "Creates a new script builder"
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc "Emits a message_start event"
  @spec emit_message_start(t(), keyword()) :: t()
  def emit_message_start(builder, opts \\ []) do
    event = MockCLI.message_start_event(opts)
    add_step(builder, {:emit, event})
  end

  @doc "Emits a text_delta event with the given text"
  @spec emit_text(t(), String.t()) :: t()
  def emit_text(builder, text) do
    event = MockCLI.text_delta_event(text)
    add_step(builder, {:emit, event})
  end

  @doc "Emits multiple text deltas (character by character or word by word)"
  @spec emit_text_stream(t(), String.t(), :chars | :words) :: t()
  def emit_text_stream(builder, text, :chars) do
    text
    |> String.graphemes()
    |> Enum.reduce(builder, fn char, acc ->
      emit_text(acc, char)
    end)
  end

  def emit_text_stream(builder, text, :words) do
    text
    |> String.split(" ")
    |> Enum.reduce(builder, fn word, acc ->
      emit_text(acc, word <> " ")
    end)
  end

  @doc "Emits a tool_use_start followed by tool input deltas"
  @spec emit_tool_use(t(), String.t(), String.t(), keyword()) :: t()
  def emit_tool_use(builder, tool_name, input_json, opts \\ []) do
    tool_id = Keyword.get(opts, :id, "tool_#{builder.current_block_index}")
    chunk_size = Keyword.get(opts, :chunk_size, 10)

    # Emit tool_use_start
    builder =
      add_step(
        builder,
        {:emit, MockCLI.tool_use_start_event(tool_name, tool_id)}
      )

    # Emit input JSON in chunks
    builder =
      input_json
      |> chunk_string(chunk_size)
      |> Enum.reduce(builder, fn chunk, acc ->
        event = MockCLI.tool_input_delta_event(chunk)
        add_step(acc, {:emit, event})
      end)

    # Increment block index for next tool
    %{builder | current_block_index: builder.current_block_index + 1}
  end

  @doc "Emits a tool_result as a control response"
  @spec emit_tool_result(t(), String.t(), String.t()) :: t()
  def emit_tool_result(builder, tool_id, result) do
    event = %{
      "type" => "sdk_message",
      "message" => %{
        "type" => "tool_result",
        "tool_use_id" => tool_id,
        "content" => result
      }
    }

    add_step(builder, {:emit, event})
  end

  @doc "Emits a message_stop event"
  @spec emit_message_stop(t()) :: t()
  def emit_message_stop(builder) do
    event = MockCLI.message_stop_event()
    add_step(builder, {:emit, event})
  end

  @doc "Adds a delay between events (in milliseconds)"
  @spec delay(t(), integer()) :: t()
  def delay(builder, ms) do
    add_step(builder, {:delay, ms})
  end

  @doc "Pauses script execution until a control request is received"
  @spec wait_for_request(t()) :: t()
  def wait_for_request(builder) do
    add_step(builder, {:wait_for_request})
  end

  @doc "Emits a thinking_start event (Sonnet 4.5+)"
  @spec emit_thinking_start(t()) :: t()
  def emit_thinking_start(builder) do
    event = %{
      "type" => "content_block_start",
      "content_block" => %{"type" => "thinking"},
      "index" => builder.current_block_index
    }

    add_step(builder, {:emit, event})
  end

  @doc "Emits thinking_delta events"
  @spec emit_thinking(t(), String.t()) :: t()
  def emit_thinking(builder, thinking_text) do
    event = %{
      "type" => "content_block_delta",
      "delta" => %{"type" => "thinking_delta", "thinking" => thinking_text},
      "index" => builder.current_block_index
    }

    add_step(builder, {:emit, event})
  end

  @doc "Emits a content_block_stop event"
  @spec emit_block_stop(t()) :: t()
  def emit_block_stop(builder) do
    event = %{
      "type" => "content_block_stop",
      "index" => builder.current_block_index
    }

    builder = add_step(builder, {:emit, event})
    %{builder | current_block_index: builder.current_block_index + 1}
  end

  @doc "Builds the final script (list of steps)"
  @spec build(t()) :: [step()]
  def build(%__MODULE__{steps: steps}) do
    Enum.reverse(steps)
  end

  ## Preset scenarios

  @doc "Creates a simple text-only streaming scenario"
  @spec simple_text_scenario(String.t()) :: [step()]
  def simple_text_scenario(text) do
    new()
    |> emit_message_start()
    |> emit_text_stream(text, :words)
    |> emit_message_stop()
    |> build()
  end

  @doc "Creates a scenario with interleaved text and single tool use"
  @spec text_with_tool_scenario(String.t(), String.t(), String.t(), String.t()) :: [step()]
  def text_with_tool_scenario(before_text, tool_name, tool_input, after_text) do
    new()
    |> emit_message_start()
    |> emit_text(before_text)
    |> emit_tool_use(tool_name, tool_input)
    |> emit_tool_result("tool_0", "success")
    |> emit_text(after_text)
    |> emit_message_stop()
    |> build()
  end

  @doc "Creates a scenario with multiple tool calls"
  @spec multi_tool_scenario([{String.t(), String.t()}]) :: [step()]
  def multi_tool_scenario(tools) do
    builder =
      new()
      |> emit_message_start()
      |> emit_text("Executing multiple tools: ")

    builder =
      Enum.reduce(tools, builder, fn {tool_name, tool_input}, acc ->
        acc
        |> emit_tool_use(tool_name, tool_input)
        |> emit_text("Tool #{tool_name} complete. ")
      end)

    builder
    |> emit_message_stop()
    |> build()
  end

  @doc "Creates a thinking + text scenario (Sonnet 4.5+)"
  @spec thinking_scenario(String.t(), String.t()) :: [step()]
  def thinking_scenario(thinking_text, response_text) do
    new()
    |> emit_message_start()
    |> emit_thinking_start()
    |> emit_thinking(thinking_text)
    |> emit_block_stop()
    |> emit_text(response_text)
    |> emit_message_stop()
    |> build()
  end

  ## Private helpers

  defp add_step(%__MODULE__{steps: steps} = builder, step) do
    %{builder | steps: [step | steps]}
  end

  defp chunk_string(string, chunk_size) do
    string
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&Enum.join/1)
  end
end
