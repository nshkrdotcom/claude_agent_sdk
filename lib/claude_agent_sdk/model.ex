defmodule ClaudeAgentSDK.Model do
  @moduledoc """
  Model validation and normalization utilities.

  This module provides functions for validating Claude model names,
  normalizing short forms to full model identifiers, and suggesting
  similar model names when an invalid model is provided.

  ## Supported Models

  - `"opus"` - Claude Opus 4.1 (claude-opus-4-1-20250805)
  - `"sonnet"` - Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)
  - `"haiku"` - Claude Haiku 4.5 (claude-haiku-4-5-20251001) - **default**
  - `"sonnet[1m]"` - Claude Sonnet 4.5 with 1M context (claude-sonnet-4-5-20250929[1m])

  ## Examples

      iex> ClaudeAgentSDK.Model.validate("opus")
      {:ok, "opus"}

      iex> ClaudeAgentSDK.Model.validate("claude-sonnet-4-5-20250929")
      {:ok, "claude-sonnet-4-5-20250929"}

      iex> ClaudeAgentSDK.Model.validate("invalid")
      {:error, :invalid_model}

      iex> ClaudeAgentSDK.Model.list_models()
      ["claude-haiku-4-5-20251001", "claude-opus-4-1-20250805", ...]

      iex> ClaudeAgentSDK.Model.suggest("opuss")
      ["opus"]
  """

  @known_models %{
    # Short forms (CLI aliases)
    "opus" => "opus",
    "sonnet" => "sonnet",
    "haiku" => "haiku",
    # 1M context variant - only sonnet[1m] works, not sonnet-1m
    "sonnet[1m]" => "sonnet[1m]",
    # Full model IDs (for reference/validation)
    "claude-opus-4-1-20250805" => "claude-opus-4-1-20250805",
    "claude-sonnet-4-5-20250929" => "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001" => "claude-haiku-4-5-20251001",
    "claude-sonnet-4-5-20250929[1m]" => "claude-sonnet-4-5-20250929[1m]"
  }

  @doc """
  Validates and normalizes a model name.

  Accepts both short forms (e.g., "opus") and full model identifiers
  (e.g., "claude-opus-4-20250514"). Returns the normalized full model
  identifier on success.

  ## Parameters

  - `model` - The model name to validate (string)

  ## Returns

  - `{:ok, normalized_model}` - When the model is valid
  - `{:error, :invalid_model}` - When the model is not recognized

  ## Examples

      iex> ClaudeAgentSDK.Model.validate("opus")
      {:ok, "opus"}

      iex> ClaudeAgentSDK.Model.validate("sonnet")
      {:ok, "sonnet"}

      iex> ClaudeAgentSDK.Model.validate("claude-haiku-4-5-20251001")
      {:ok, "claude-haiku-4-5-20251001"}

      iex> ClaudeAgentSDK.Model.validate("invalid-model")
      {:error, :invalid_model}

      iex> ClaudeAgentSDK.Model.validate(nil)
      {:error, :invalid_model}

      iex> ClaudeAgentSDK.Model.validate("")
      {:error, :invalid_model}
  """
  @spec validate(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_model}
  def validate(model) when is_binary(model) and model != "" do
    case Map.get(@known_models, model) do
      nil -> {:error, :invalid_model}
      normalized -> {:ok, normalized}
    end
  end

  def validate(_), do: {:error, :invalid_model}

  @doc """
  Returns a sorted list of all known model names.

  The list includes both short forms and full model identifiers.

  ## Returns

  A sorted list of model name strings.

  ## Examples

      iex> models = ClaudeAgentSDK.Model.list_models()
      iex> "opus" in models
      true

      iex> models = ClaudeAgentSDK.Model.list_models()
      iex> "claude-opus-4-20250514" in models
      true

      iex> models = ClaudeAgentSDK.Model.list_models()
      iex> models == Enum.sort(models)
      true
  """
  @spec list_models() :: [String.t()]
  def list_models do
    @known_models
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Suggests similar model names for an invalid input.

  Uses Jaro distance algorithm to find models with similarity > 0.7.
  Returns up to 3 suggestions, sorted by similarity (highest first).

  ## Parameters

  - `invalid_model` - The invalid model name to find suggestions for

  ## Returns

  A list of up to 3 suggested model names, or an empty list if no
  similar models are found.

  ## Examples

      iex> ClaudeAgentSDK.Model.suggest("opuss")
      ["opus", "claude-opus-4-20250514"]

      iex> ClaudeAgentSDK.Model.suggest("sonet")
      ["sonnet", "claude-sonnet-4-20250514"]

      iex> ClaudeAgentSDK.Model.suggest("completely-unrelated-xyz123")
      []

      iex> suggestions = ClaudeAgentSDK.Model.suggest("claude")
      iex> length(suggestions) <= 3
      true
  """
  @spec suggest(String.t()) :: [String.t()]
  def suggest(invalid_model) when is_binary(invalid_model) do
    @known_models
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
