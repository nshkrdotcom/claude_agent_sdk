defmodule ClaudeAgentSDK.Test.ModelFixtures do
  @moduledoc """
  Shared model constants for tests.

  Provides stable model identifiers for use in test fixtures, eliminating
  hardcoded model strings scattered across test files. These are arbitrary
  test strings -- they do NOT need to match real Claude model IDs unless a
  test specifically validates the model registry itself.

  ## Usage

      import ClaudeAgentSDK.Test.ModelFixtures

      test "handles message_start event" do
        event = %{"type" => "message_start", "message" => %{"model" => test_model()}}
        ...
      end
  """

  @doc "Primary model string for test fixtures."
  def test_model, do: "test-model-alpha"

  @doc "Alternate model string for tests that need two distinct models."
  def test_model_alt, do: "test-model-beta"

  @doc "Returns the SDK's current default model from the live registry."
  def real_default_model, do: ClaudeAgentSDK.Model.default_model()
end
