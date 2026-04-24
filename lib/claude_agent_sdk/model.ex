defmodule ClaudeAgentSDK.Model do
  @moduledoc """
  Core-backed Claude model helpers.
  """

  alias CliSubprocessCore.{ModelCatalog, ModelRegistry}

  @spec known_models() :: %{String.t() => String.t()}
  def known_models do
    catalog_entries()
    |> Enum.reduce(%{}, fn {id, aliases}, acc ->
      acc
      |> Map.put(id, id)
      |> Map.merge(Map.new(aliases, &{&1, &1}))
    end)
  end

  @spec default_model() :: String.t()
  def default_model do
    case ModelRegistry.default_model(:claude) do
      {:ok, model} ->
        model

      {:error, reason} ->
        raise ArgumentError, "claude model registry default_model failed: #{inspect(reason)}"
    end
  end

  @spec short_forms() :: [String.t()]
  def short_forms do
    catalog_entries()
    |> Enum.map(fn {id, _aliases} -> id end)
    |> Enum.sort()
  end

  @spec full_ids() :: [String.t()]
  def full_ids do
    catalog_entries()
    |> Enum.flat_map(fn {_id, aliases} ->
      Enum.filter(aliases, &String.starts_with?(&1, "claude-"))
    end)
    |> Enum.sort()
  end

  @spec validate(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_model}
  def validate(model) when is_binary(model) and model != "" do
    case ModelRegistry.validate(:claude, model) do
      {:ok, _model} -> {:ok, model}
      {:error, _reason} -> {:error, :invalid_model}
    end
  end

  def validate(_model), do: {:error, :invalid_model}

  @spec list_models() :: [String.t()]
  def list_models do
    (short_forms() ++ full_ids())
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec suggest(String.t()) :: [String.t()]
  def suggest(invalid_model) when is_binary(invalid_model) do
    list_models()
    |> Enum.map(fn model ->
      {model, String.jaro_distance(invalid_model, model)}
    end)
    |> Enum.filter(fn {_model, distance} -> distance > 0.7 end)
    |> Enum.sort_by(fn {_model, distance} -> distance end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {model, _distance} -> model end)
  end

  def suggest(_invalid_model), do: []

  defp catalog_entries do
    case ModelCatalog.load(:claude) do
      {:ok, catalog} ->
        catalog.models
        |> Enum.filter(&(&1.visibility == :public))
        |> Enum.map(fn model -> {model.id, model.aliases} end)

      {:error, _reason} ->
        []
    end
  end
end
