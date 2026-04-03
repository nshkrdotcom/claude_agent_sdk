defmodule ExternalRuntimeTransport.TestSupport.GuestLocalAdapter do
  @moduledoc false

  alias ExternalRuntimeTransport.Command
  alias ExternalRuntimeTransport.ExecutionSurface.Adapter
  alias ExternalRuntimeTransport.ExecutionSurface.Capabilities
  alias ExternalRuntimeTransport.Transport
  alias ExternalRuntimeTransport.Transport.Subprocess

  @behaviour Adapter
  @behaviour Transport

  @impl Adapter
  def surface_kind, do: :test_guest_local

  @impl Adapter
  def capabilities do
    Capabilities.new!(
      remote?: false,
      startup_kind: :spawn,
      path_semantics: :guest,
      supports_run?: true,
      supports_streaming_stdio?: true,
      supports_pty?: true,
      supports_user?: true,
      supports_env?: true,
      supports_cwd?: true,
      interrupt_kind: :signal
    )
  end

  @impl Adapter
  def normalize_transport_options(nil), do: {:ok, []}

  def normalize_transport_options(options) when is_list(options) do
    if Keyword.keyword?(options) and options == [] do
      {:ok, []}
    else
      {:error, {:invalid_transport_options, options}}
    end
  end

  def normalize_transport_options(options) when is_map(options) and map_size(options) == 0,
    do: {:ok, []}

  def normalize_transport_options(options), do: {:error, {:invalid_transport_options, options}}

  @impl Transport
  def start(opts) when is_list(opts), do: Subprocess.start(strip_local_cwd(opts))

  @impl Transport
  def start_link(opts) when is_list(opts), do: Subprocess.start_link(strip_local_cwd(opts))

  @impl Transport
  def run(%Command{} = command, opts) when is_list(opts) do
    Subprocess.run(%Command{command | cwd: nil}, strip_local_cwd(opts))
  end

  @impl Transport
  defdelegate send(transport, message), to: Subprocess

  @impl Transport
  defdelegate subscribe(transport, pid), to: Subprocess

  @impl Transport
  defdelegate subscribe(transport, pid, tag), to: Subprocess

  @impl Transport
  defdelegate unsubscribe(transport, pid), to: Subprocess

  @impl Transport
  defdelegate close(transport), to: Subprocess

  @impl Transport
  defdelegate force_close(transport), to: Subprocess

  @impl Transport
  defdelegate interrupt(transport), to: Subprocess

  @impl Transport
  defdelegate status(transport), to: Subprocess

  @impl Transport
  defdelegate end_input(transport), to: Subprocess

  @impl Transport
  defdelegate stderr(transport), to: Subprocess

  @impl Transport
  defdelegate info(transport), to: Subprocess

  defp strip_local_cwd(opts) when is_list(opts) do
    opts
    |> Keyword.update(:command, nil, &strip_command_cwd/1)
    |> Keyword.delete(:cwd)
  end

  defp strip_command_cwd(%Command{} = command), do: %Command{command | cwd: nil}
  defp strip_command_cwd(other), do: other
end
