defmodule Examples.Support do
  @moduledoc false

  alias ClaudeAgentSDK.{CLI, Mock}

  @examples_dir Path.expand("..", __DIR__)

  def examples_dir, do: @examples_dir

  def output_dir! do
    dir = Path.join(@examples_dir, "_output")
    File.mkdir_p!(dir)
    dir
  end

  def ensure_mock! do
    Application.put_env(:claude_agent_sdk, :use_mock, true)

    case Mock.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  def ensure_live! do
    Application.put_env(:claude_agent_sdk, :use_mock, false)

    case CLI.find_executable() do
      {:ok, _path} ->
        :ok

      {:error, :not_found} ->
        raise "Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    end
  end

  def mode(argv \\ System.argv()) when is_list(argv) do
    if Enum.member?(argv, "--live"), do: :live, else: :mock
  end

  def init!(argv \\ System.argv()) do
    case mode(argv) do
      :live ->
        ensure_live!()
        :live

      :mock ->
        {:ok, _} = ensure_mock!()
        :mock
    end
  end

  def header!(title) when is_binary(title) do
    IO.puts("\n" <> String.duplicate("=", 72))
    IO.puts(title)
    IO.puts(String.duplicate("=", 72))
    :ok
  end
end
