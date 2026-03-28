defmodule ClaudeAgentSDK.TestSupport.FakeCLI do
  @moduledoc false

  alias ClaudeAgentSDK.Options
  alias CliSubprocessCore.TestSupport.FakeSSH

  defstruct root_dir: nil,
            script_path: nil,
            requests_path: nil,
            stdout_dir: nil,
            stderr_dir: nil,
            started_path: nil,
            stdin_closed_path: nil,
            shutdown_path: nil,
            shutdown_ack_path: nil

  @type t :: %__MODULE__{
          root_dir: String.t(),
          script_path: String.t(),
          requests_path: String.t(),
          stdout_dir: String.t(),
          stderr_dir: String.t(),
          started_path: String.t(),
          stdin_closed_path: String.t(),
          shutdown_path: String.t(),
          shutdown_ack_path: String.t()
        }

  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    root_dir = Keyword.get(opts, :root_dir, temp_dir!("claude_agent_sdk_fake_cli"))
    stdout_dir = Path.join(root_dir, "stdout_queue")
    stderr_dir = Path.join(root_dir, "stderr_queue")
    requests_path = Path.join(root_dir, "requests.log")
    started_path = Path.join(root_dir, "started")
    stdin_closed_path = Path.join(root_dir, "stdin_closed")
    shutdown_path = Path.join(root_dir, "shutdown")
    shutdown_ack_path = Path.join(root_dir, "shutdown_ack")
    script_path = Path.join(root_dir, "fake_claude")

    File.mkdir_p!(stdout_dir)
    File.mkdir_p!(stderr_dir)
    File.write!(script_path, script_contents(root_dir))
    File.chmod!(script_path, 0o755)

    %__MODULE__{
      root_dir: root_dir,
      script_path: script_path,
      requests_path: requests_path,
      stdout_dir: stdout_dir,
      stderr_dir: stderr_dir,
      started_path: started_path,
      stdin_closed_path: stdin_closed_path,
      shutdown_path: shutdown_path,
      shutdown_ack_path: shutdown_ack_path
    }
  end

  @spec cleanup(t()) :: :ok
  def cleanup(%__MODULE__{
        root_dir: root_dir,
        shutdown_path: shutdown_path,
        shutdown_ack_path: shutdown_ack_path
      })
      when is_binary(root_dir) do
    if File.dir?(root_dir) do
      _ = File.write(shutdown_path, "")
      _ = wait_until(fn -> File.exists?(shutdown_ack_path) or not File.dir?(root_dir) end, 250)
      remove_root_dir!(root_dir)
    end

    :ok
  end

  @spec wait_until_started(t(), non_neg_integer()) :: :ok | :timeout
  def wait_until_started(%__MODULE__{started_path: started_path}, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    case wait_until(fn -> File.exists?(started_path) end, timeout_ms) do
      {:ok, _result} -> :ok
      :timeout -> :timeout
    end
  end

  @spec wait_until_stdin_closed(t(), non_neg_integer()) :: :ok | :timeout
  def wait_until_stdin_closed(%__MODULE__{stdin_closed_path: stdin_closed_path}, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    case wait_until(fn -> File.exists?(stdin_closed_path) end, timeout_ms) do
      {:ok, _result} -> :ok
      :timeout -> :timeout
    end
  end

  @spec wait_for_request_count(t(), non_neg_integer(), non_neg_integer()) :: :ok | :timeout
  def wait_for_request_count(%__MODULE__{} = fake_cli, count, timeout_ms)
      when is_integer(count) and count >= 0 and is_integer(timeout_ms) and timeout_ms >= 0 do
    case wait_until(fn -> length(recorded_messages(fake_cli)) >= count end, timeout_ms) do
      {:ok, _result} -> :ok
      :timeout -> :timeout
    end
  end

  @spec recorded_messages(t()) :: [binary()]
  def recorded_messages(%__MODULE__{requests_path: requests_path}) do
    case File.read(requests_path) do
      {:ok, contents} -> split_lines(contents)
      {:error, :enoent} -> []
      {:error, reason} -> raise File.Error, reason: reason, action: "read", path: requests_path
    end
  end

  @spec decoded_messages(t()) :: [map()]
  def decoded_messages(%__MODULE__{} = fake_cli) do
    fake_cli
    |> recorded_messages()
    |> Enum.map(&Jason.decode!/1)
  end

  @spec wait_for_decoded_message(t(), (map() -> boolean()), non_neg_integer()) ::
          {:ok, map()} | {:error, :timeout}
  def wait_for_decoded_message(%__MODULE__{} = fake_cli, matcher, timeout_ms)
      when is_function(matcher, 1) and is_integer(timeout_ms) and timeout_ms >= 0 do
    case wait_until(fn -> Enum.find(decoded_messages(fake_cli), matcher) end, timeout_ms) do
      {:ok, %{} = message} -> {:ok, message}
      :timeout -> {:error, :timeout}
    end
  end

  @spec wait_for_control_response(t(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, :timeout}
  def wait_for_control_response(%__MODULE__{} = fake_cli, request_id, timeout_ms \\ 1_000)
      when is_binary(request_id) and is_integer(timeout_ms) and timeout_ms >= 0 do
    wait_for_decoded_message(
      fake_cli,
      fn
        %{"type" => "control_response", "response" => %{"request_id" => ^request_id}} -> true
        _ -> false
      end,
      timeout_ms
    )
  end

  @spec options(t(), Options.t(), keyword()) :: Options.t()
  def options(%__MODULE__{} = fake_cli, %Options{} = options, opts \\ []) when is_list(opts) do
    execution_surface =
      Keyword.get(opts, :execution_surface, Map.get(options, :execution_surface))

    options
    |> Map.from_struct()
    |> Map.merge(%{
      path_to_claude_code_executable: fake_cli.script_path,
      execution_surface: execution_surface
    })
    |> then(&struct(Options, &1))
  end

  @spec push_message(t(), map() | binary()) :: :ok
  def push_message(%__MODULE__{} = fake_cli, payload) do
    enqueue(fake_cli.stdout_dir, payload, :line)
  end

  @spec push_stderr(t(), map() | binary()) :: :ok
  def push_stderr(%__MODULE__{} = fake_cli, payload) do
    enqueue(fake_cli.stderr_dir, payload, :line)
  end

  @spec push_raw_message(t(), binary()) :: :ok
  def push_raw_message(%__MODULE__{} = fake_cli, payload) when is_binary(payload) do
    enqueue(fake_cli.stdout_dir, payload, :raw)
  end

  @spec push_raw_stderr(t(), binary()) :: :ok
  def push_raw_stderr(%__MODULE__{} = fake_cli, payload) when is_binary(payload) do
    enqueue(fake_cli.stderr_dir, payload, :raw)
  end

  @spec initialize_request(t(), non_neg_integer()) :: {:ok, map()} | {:error, :timeout}
  def initialize_request(%__MODULE__{} = fake_cli, timeout_ms \\ 1_000)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    case wait_until(
           fn -> Enum.find(decoded_messages(fake_cli), &initialize_request?/1) end,
           timeout_ms
         ) do
      {:ok, %{} = request} -> {:ok, request}
      :timeout -> {:error, :timeout}
    end
  end

  @spec respond_initialize_success!(t(), map(), non_neg_integer()) :: String.t()
  def respond_initialize_success!(%__MODULE__{} = fake_cli, response \\ %{}, timeout_ms \\ 1_000)
      when is_map(response) and is_integer(timeout_ms) and timeout_ms >= 0 do
    {:ok, request} =
      case initialize_request(fake_cli, timeout_ms) do
        {:ok, request} -> {:ok, request}
        {:error, :timeout} -> raise "timed out waiting for initialize request"
      end

    request_id = request["request_id"]

    push_message(fake_cli, %{
      "type" => "control_response",
      "response" => %{
        "subtype" => "success",
        "request_id" => request_id,
        "response" => response
      }
    })

    request_id
  end

  @spec static_ssh_surface(t(), FakeSSH.t(), keyword()) :: keyword()
  def static_ssh_surface(%__MODULE__{}, %FakeSSH{} = fake_ssh, opts \\ []) when is_list(opts) do
    destination = Keyword.get(opts, :destination, "claude-sdk.test.example")
    user = Keyword.get(opts, :user, "sdk")
    port = Keyword.get(opts, :port, 22)

    [
      surface_kind: :static_ssh,
      transport_options:
        FakeSSH.transport_options(fake_ssh,
          destination: destination,
          user: user,
          port: port
        )
    ]
  end

  defp enqueue(queue_dir, payload, mode) when is_binary(payload) do
    suffix =
      case mode do
        :raw -> ".raw"
        _ -> ".frame"
      end

    sequence =
      System.unique_integer([:positive, :monotonic])
      |> Integer.to_string()
      |> String.pad_leading(20, "0")

    path = Path.join(queue_dir, "#{sequence}#{suffix}")
    File.write!(path, payload)
    :ok
  end

  defp enqueue(queue_dir, payload, mode) when is_map(payload) or is_list(payload) do
    queue_dir
    |> enqueue(Jason.encode!(payload), mode)
  end

  defp split_lines(contents) when is_binary(contents) do
    contents
    |> :binary.split("\n", [:global])
    |> Enum.reject(&(&1 == ""))
  end

  defp initialize_request?(%{
         "type" => "control_request",
         "request" => %{"subtype" => "initialize"}
       }),
       do: true

  defp initialize_request?(_message), do: false

  defp script_contents(root_dir) do
    """
    #!/usr/bin/env python3
    import os
    import pathlib
    import select
    import sys
    import time

    ROOT = #{inspect(root_dir)}
    REQUESTS_PATH = os.path.join(ROOT, "requests.log")
    STARTED_PATH = os.path.join(ROOT, "started")
    STDIN_CLOSED_PATH = os.path.join(ROOT, "stdin_closed")
    SHUTDOWN_PATH = os.path.join(ROOT, "shutdown")
    SHUTDOWN_ACK_PATH = os.path.join(ROOT, "shutdown_ack")
    STDOUT_DIR = os.path.join(ROOT, "stdout_queue")
    STDERR_DIR = os.path.join(ROOT, "stderr_queue")

    try:
        pathlib.Path(STARTED_PATH).touch()
    except FileNotFoundError:
        sys.exit(0)

    def flush_queue(queue_dir, stream):
        processed = False
        exists = True

        try:
            entries = sorted(os.listdir(queue_dir))
        except FileNotFoundError:
            return processed, False

        for name in entries:
            path = os.path.join(queue_dir, name)

            if not os.path.isfile(path):
                continue

            with open(path, "rb") as handle:
                payload = handle.read()

            os.remove(path)

            if payload and not name.endswith(".raw") and not payload.endswith(b"\\n"):
                payload += b"\\n"

            stream.write(payload)
            stream.flush()
            processed = True

        return processed, exists

    stdin_open = True
    idle_cycles_after_eof = 0

    while True:
        processed = False

        if os.path.exists(SHUTDOWN_PATH):
            break

        stdout_processed, stdout_exists = flush_queue(STDOUT_DIR, sys.stdout.buffer)

        if not stdout_exists:
            break

        if stdout_processed:
            processed = True

        stderr_processed, stderr_exists = flush_queue(STDERR_DIR, sys.stderr.buffer)

        if not stderr_exists:
            break

        if stderr_processed:
            processed = True

        if stdin_open:
            ready, _, _ = select.select([sys.stdin.buffer], [], [], 0.02)

            if ready:
                line = sys.stdin.buffer.readline()

                if line == b"":
                    stdin_open = False

                    try:
                        pathlib.Path(STDIN_CLOSED_PATH).touch()
                    except FileNotFoundError:
                        break

                    processed = True
                else:
                    try:
                        with open(REQUESTS_PATH, "ab") as handle:
                            if line.endswith(b"\\n"):
                                handle.write(line)
                            else:
                                handle.write(line + b"\\n")
                    except FileNotFoundError:
                        break

                    processed = True
        else:
            if processed:
                idle_cycles_after_eof = 0
            else:
                idle_cycles_after_eof += 1

                if idle_cycles_after_eof >= 50:
                    break

        if not processed:
            time.sleep(0.02)

    try:
        pathlib.Path(SHUTDOWN_ACK_PATH).touch()
    except FileNotFoundError:
        pass
    """
  end

  defp temp_dir!(prefix) when is_binary(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp wait_until(fun, timeout_ms) when is_function(fun, 0) and is_integer(timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline_ms)
  end

  defp remove_root_dir!(root_dir, attempts \\ 5)

  defp remove_root_dir!(root_dir, attempts) when attempts > 0 do
    case File.rm_rf(root_dir) do
      {:ok, _removed} ->
        :ok

      {:error, reason, _path} ->
        if attempts == 1 do
          raise File.Error,
            reason: reason,
            action: "remove files and directories recursively from",
            path: root_dir
        else
          Process.sleep(25)
          remove_root_dir!(root_dir, attempts - 1)
        end
    end
  end

  defp do_wait_until(fun, deadline_ms) do
    case fun.() do
      result when result not in [false, nil] ->
        {:ok, result}

      _ ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          :timeout
        else
          Process.sleep(10)
          do_wait_until(fun, deadline_ms)
        end
    end
  end
end
