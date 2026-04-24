defmodule ClaudeAgentSDK.SessionStore.Key do
  @moduledoc """
  Identifies a main session transcript or subagent transcript in a SessionStore.

  Main transcripts omit `subpath`. Subagent transcripts use portable `/` joined
  paths such as `"subagents/agent-abc"`.
  """

  @enforce_keys [:project_key, :session_id]
  defstruct [:project_key, :session_id, :subpath]

  @type t :: %__MODULE__{
          project_key: String.t(),
          session_id: String.t(),
          subpath: String.t() | nil
        }

  @type input :: t() | %{optional(atom() | String.t()) => term()} | keyword()

  @doc false
  @spec new!(input()) :: t()
  def new!(%__MODULE__{} = key), do: validate!(key)

  def new!(key) when is_list(key) do
    key
    |> Map.new()
    |> new!()
  end

  def new!(%{} = key) do
    %__MODULE__{
      project_key: value(key, :project_key),
      session_id: value(key, :session_id),
      subpath: normalize_subpath(value(key, :subpath))
    }
    |> validate!()
  end

  @doc false
  @spec to_map(t() | input()) :: map()
  def to_map(key) do
    key = new!(key)
    base = %{project_key: key.project_key, session_id: key.session_id}

    if is_binary(key.subpath) and key.subpath != "" do
      Map.put(base, :subpath, key.subpath)
    else
      base
    end
  end

  @doc false
  @spec storage_key(t() | input()) :: {String.t(), String.t(), String.t() | nil}
  def storage_key(key) do
    key = new!(key)
    {key.project_key, key.session_id, key.subpath}
  end

  @doc false
  @spec main?(t() | input()) :: boolean()
  def main?(key), do: is_nil(new!(key).subpath)

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp normalize_subpath(nil), do: nil
  defp normalize_subpath(""), do: nil
  defp normalize_subpath(subpath) when is_binary(subpath), do: subpath
  defp normalize_subpath(other), do: other

  defp validate!(
         %__MODULE__{project_key: project_key, session_id: session_id, subpath: subpath} = key
       ) do
    unless nonempty_binary?(project_key) do
      raise ArgumentError, "SessionStore key project_key must be a non-empty string"
    end

    unless nonempty_binary?(session_id) do
      raise ArgumentError, "SessionStore key session_id must be a non-empty string"
    end

    if not is_nil(subpath) and not nonempty_binary?(subpath) do
      raise ArgumentError, "SessionStore key subpath must be omitted or a non-empty string"
    end

    key
  end

  defp nonempty_binary?(value), do: is_binary(value) and String.trim(value) != ""
end
