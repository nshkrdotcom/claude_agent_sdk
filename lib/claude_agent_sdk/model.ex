defmodule ClaudeAgentSDK.Model do
  @moduledoc """
  Config-driven model validation and normalization.

  All known models are read at runtime from application config, so new
  models can be added without recompilation.

  ## Configuration

  Models are configured in `config/config.exs` (or any environment overlay):

      config :claude_agent_sdk, :models, %{
        short_forms: %{
          "opus"       => "opus",
          "sonnet"     => "sonnet",
          "haiku"      => "haiku",
          "sonnet[1m]" => "sonnet[1m]"
        },
        full_ids: %{
          "claude-opus-4-6"                => "claude-opus-4-6",
          "claude-sonnet-4-5-20250929"     => "claude-sonnet-4-5-20250929",
          "claude-haiku-4-5-20251001"      => "claude-haiku-4-5-20251001",
          "claude-sonnet-4-5-20250929[1m]" => "claude-sonnet-4-5-20250929[1m]"
        },
        default: "haiku"
      }

  SDK consumers can add custom models at runtime:

      config = Application.get_env(:claude_agent_sdk, :models)
      updated = Map.update!(config, :full_ids, &Map.put(&1, "my-custom-model", "my-custom-model"))
      Application.put_env(:claude_agent_sdk, :models, updated)

  See the **Model Configuration** guide for details.

  ## Examples

      iex> ClaudeAgentSDK.Model.validate("opus")
      {:ok, "opus"}

      iex> ClaudeAgentSDK.Model.validate("invalid")
      {:error, :invalid_model}

      iex> "opus" in ClaudeAgentSDK.Model.list_models()
      true

      iex> ClaudeAgentSDK.Model.suggest("opuss")
      ["opus"]
  """

  @doc """
  Returns the merged map of all known models (short forms + full IDs).
  """
  @spec known_models() :: %{String.t() => String.t()}
  def known_models do
    config = Application.get_env(:claude_agent_sdk, :models, %{})

    Map.merge(
      Map.get(config, :short_forms, %{}),
      Map.get(config, :full_ids, %{})
    )
  end

  @doc """
  Returns the configured default model name.
  """
  @spec default_model() :: String.t()
  def default_model do
    config = Application.get_env(:claude_agent_sdk, :models, %{})
    Map.get(config, :default, "haiku")
  end

  @doc """
  Returns the list of configured short-form aliases.
  """
  @spec short_forms() :: [String.t()]
  def short_forms do
    config = Application.get_env(:claude_agent_sdk, :models, %{})
    config |> Map.get(:short_forms, %{}) |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns the list of configured full model identifiers.
  """
  @spec full_ids() :: [String.t()]
  def full_ids do
    config = Application.get_env(:claude_agent_sdk, :models, %{})
    config |> Map.get(:full_ids, %{}) |> Map.keys() |> Enum.sort()
  end

  @doc """
  Validates and normalizes a model name.

  Accepts both short forms (e.g., `"opus"`) and full model identifiers.
  Returns the normalized value on success.

  ## Examples

      iex> ClaudeAgentSDK.Model.validate("opus")
      {:ok, "opus"}

      iex> ClaudeAgentSDK.Model.validate("sonnet")
      {:ok, "sonnet"}

      iex> ClaudeAgentSDK.Model.validate("invalid-model")
      {:error, :invalid_model}

      iex> ClaudeAgentSDK.Model.validate(nil)
      {:error, :invalid_model}

      iex> ClaudeAgentSDK.Model.validate("")
      {:error, :invalid_model}
  """
  @spec validate(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_model}
  def validate(model) when is_binary(model) and model != "" do
    case Map.get(known_models(), model) do
      nil -> {:error, :invalid_model}
      normalized -> {:ok, normalized}
    end
  end

  def validate(_), do: {:error, :invalid_model}

  @doc """
  Returns a sorted list of all known model names.

  The list includes both short forms and full model identifiers.

  ## Examples

      iex> models = ClaudeAgentSDK.Model.list_models()
      iex> "opus" in models
      true

      iex> models = ClaudeAgentSDK.Model.list_models()
      iex> models == Enum.sort(models)
      true
  """
  @spec list_models() :: [String.t()]
  def list_models do
    known_models()
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Suggests similar model names for an invalid input.

  Uses Jaro distance algorithm to find models with similarity > 0.7.
  Returns up to 3 suggestions, sorted by similarity (highest first).

  ## Examples

      iex> ClaudeAgentSDK.Model.suggest("opuss")
      ["opus"]

      iex> ClaudeAgentSDK.Model.suggest("completely-unrelated-xyz123")
      []

      iex> suggestions = ClaudeAgentSDK.Model.suggest("claude")
      iex> length(suggestions) <= 3
      true
  """
  @spec suggest(String.t()) :: [String.t()]
  def suggest(invalid_model) when is_binary(invalid_model) do
    known_models()
    |> Map.keys()
    |> Enum.map(fn model ->
      {model, String.jaro_distance(invalid_model, model)}
    end)
    |> Enum.filter(fn {_model, distance} -> distance > 0.7 end)
    |> Enum.sort_by(fn {_model, distance} -> distance end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {model, _distance} -> model end)
  end

  def suggest(_), do: []
end
