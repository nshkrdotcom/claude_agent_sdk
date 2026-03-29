defmodule Examples.Support do
  @moduledoc false

  alias ClaudeAgentSDK.CLI
  alias ClaudeAgentSDK.ExamplesSupport
  alias ClaudeAgentSDK.Options

  @examples_dir Path.expand("..", __DIR__)

  def init!(argv \\ System.argv()), do: ExamplesSupport.init!(argv)

  def with_execution_surface(options), do: ExamplesSupport.with_execution_surface(options)

  def ssh_enabled?, do: ExamplesSupport.ssh_enabled?()

  def examples_dir, do: @examples_dir

  def output_dir! do
    dir = Path.join(@examples_dir, "_output")
    File.mkdir_p!(dir)
    dir
  end

  def tmp_dir!(prefix) when is_binary(prefix) do
    suffix = "#{System.system_time(:microsecond)}_#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{suffix}")
    File.mkdir_p!(dir)
    dir
  end

  def cleanup_tmp_dir(nil), do: :ok

  def cleanup_tmp_dir(path) when is_binary(path) do
    _ = File.rm_rf(path)
    :ok
  end

  def ollama_backend? do
    case normalized_env("CLAUDE_AGENT_PROVIDER_BACKEND") ||
           normalized_env("CLAUDE_EXAMPLES_BACKEND") do
      "ollama" ->
        true

      _ ->
        System.get_env("ANTHROPIC_AUTH_TOKEN") == "ollama" and
          case System.get_env("ANTHROPIC_BASE_URL") do
            nil -> false
            value -> String.trim(value) != ""
          end
    end
  end

  def force_unsupported_examples? do
    truthy_env?("CLAUDE_EXAMPLES_FORCE_UNSUPPORTED")
  end

  def maybe_skip_for_ollama!(example_name, reason)
      when is_binary(example_name) and is_binary(reason) do
    if ollama_backend?() and not force_unsupported_examples?() do
      IO.puts("Skipping #{example_name} under Ollama.")
      IO.puts(reason)
      IO.puts("Set CLAUDE_EXAMPLES_FORCE_UNSUPPORTED=true to run it anyway.")
      halt_if_runner!(0)
      System.halt(0)
    end

    :ok
  end

  # When running under `examples/run_all.sh`, we force-halt to avoid any cases where
  # background OTP apps or ports keep the VM alive after the script finishes.
  def halt_if_runner!(exit_code \\ 0) when is_integer(exit_code) do
    case System.get_env("CLAUDE_EXAMPLES_FORCE_HALT") do
      nil ->
        :ok

      value when is_binary(value) ->
        value = value |> String.trim() |> String.downcase()

        if value in ["1", "true", "yes", "y", "on"] do
          :erlang.halt(exit_code)
        end
    end

    :ok
  end

  def ensure_live! do
    init!()
    Application.put_env(:claude_agent_sdk, :use_mock, false)
    ensure_task_supervisor_started!()

    options =
      %Options{}
      |> with_execution_surface()

    case CLI.resolve_executable(options) do
      {:ok, _path} ->
        :ok

      {:error, :not_found} ->
        raise """
        Claude CLI not found.

        Install:
          npm install -g @anthropic-ai/claude-code

        Then authenticate:
          claude login
        """
    end
  end

  defp ensure_task_supervisor_started! do
    case ClaudeAgentSDK.TaskSupervisor.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      other ->
        raise "Failed to start ClaudeAgentSDK.TaskSupervisor: #{inspect(other)}"
    end
  end

  def header!(title) when is_binary(title) do
    IO.puts("\n" <> String.duplicate("=", 72))
    IO.puts(title)
    IO.puts(String.duplicate("=", 72))
    :ok
  end

  def format_cost(cost) when is_integer(cost), do: format_cost(cost * 1.0)
  def format_cost(cost) when is_float(cost), do: :erlang.float_to_binary(cost, decimals: 6)

  def assert_exact_text!(text, expected, label \\ "response")
      when is_binary(text) and is_binary(expected) and is_binary(label) do
    actual = String.trim(text)

    if actual != expected do
      raise "#{label} mismatch: expected #{inspect(expected)}, got #{inspect(actual)}"
    end

    actual
  end

  defp normalized_env(name) when is_binary(name) do
    case System.get_env(name) do
      nil -> nil
      value -> value |> String.trim() |> String.downcase()
    end
  end

  defp truthy_env?(name) when is_binary(name) do
    case normalized_env(name) do
      value when value in ["1", "true", "yes", "y", "on"] -> true
      _ -> false
    end
  end
end
