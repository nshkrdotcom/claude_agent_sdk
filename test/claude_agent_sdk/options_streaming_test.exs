defmodule ClaudeAgentSDK.OptionsStreamingTest do
  @moduledoc """
  Tests for streaming-related Options functionality (v0.6.0).

  Tests the new fields added for streaming + tools unification:
  - include_partial_messages
  - preferred_transport
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Options

  describe "include_partial_messages field" do
    test "creates options with include_partial_messages set to true" do
      options = Options.new(include_partial_messages: true)
      assert options.include_partial_messages == true
    end

    test "creates options with include_partial_messages set to false" do
      options = Options.new(include_partial_messages: false)
      assert options.include_partial_messages == false
    end

    test "defaults to nil when not specified" do
      options = Options.new()
      assert options.include_partial_messages == nil
    end

    test "includes --include-partial-messages flag when true" do
      options = %Options{include_partial_messages: true}
      args = Options.to_args(options)
      assert "--include-partial-messages" in args
    end

    test "omits --include-partial-messages flag when false" do
      options = %Options{include_partial_messages: false}
      args = Options.to_args(options)
      refute "--include-partial-messages" in args
    end

    test "omits --include-partial-messages flag when nil" do
      options = %Options{include_partial_messages: nil}
      args = Options.to_args(options)
      refute "--include-partial-messages" in args
    end

    test "includes flag at end of arguments pipeline" do
      options = %Options{
        model: "sonnet",
        verbose: true,
        include_partial_messages: true
      }

      args = Options.to_args(options)

      # Should be in the args list
      assert "--include-partial-messages" in args

      # Should come after other flags
      model_idx = Enum.find_index(args, &(&1 == "--model"))
      partial_idx = Enum.find_index(args, &(&1 == "--include-partial-messages"))

      assert model_idx < partial_idx
    end
  end

  describe "preferred_transport field" do
    test "creates options with preferred_transport :cli" do
      options = Options.new(preferred_transport: :cli)
      assert options.preferred_transport == :cli
    end

    test "creates options with preferred_transport :control" do
      options = Options.new(preferred_transport: :control)
      assert options.preferred_transport == :control
    end

    test "creates options with preferred_transport :auto" do
      options = Options.new(preferred_transport: :auto)
      assert options.preferred_transport == :auto
    end

    test "defaults to nil when not specified" do
      options = Options.new()
      assert options.preferred_transport == nil
    end

    test "does not add CLI arguments (used only by router)" do
      # preferred_transport is not a CLI flag, it's for internal routing
      options = %Options{preferred_transport: :cli}
      args = Options.to_args(options)

      # Should not contain any transport-related CLI flags
      refute "--preferred-transport" in args
      refute "--transport" in args
      refute "cli" in args
      refute "control" in args
    end
  end

  describe "combined streaming features" do
    test "can set both streaming fields together" do
      options =
        Options.new(
          include_partial_messages: true,
          preferred_transport: :control
        )

      assert options.include_partial_messages == true
      assert options.preferred_transport == :control
    end

    test "streaming fields work with other options" do
      options =
        Options.new(
          model: "sonnet",
          max_turns: 10,
          verbose: true,
          include_partial_messages: true,
          preferred_transport: :auto
        )

      assert options.model == "sonnet"
      assert options.max_turns == 10
      assert options.verbose == true
      assert options.include_partial_messages == true
      assert options.preferred_transport == :auto
    end

    test "generates correct CLI args with streaming and standard options" do
      options = %Options{
        model: "opus",
        max_turns: 5,
        verbose: true,
        include_partial_messages: true
      }

      args = Options.to_args(options)

      # Should have all expected flags
      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "5" in args
      assert "--verbose" in args
      assert "--include-partial-messages" in args
    end
  end

  describe "struct validation" do
    test "accepts valid options struct" do
      options = %Options{
        include_partial_messages: true,
        preferred_transport: :cli
      }

      # Should not raise
      assert %Options{} = options
    end

    test "struct has correct types" do
      options = %Options{}

      # Verify field exists and has correct default
      assert Map.has_key?(options, :include_partial_messages)
      assert Map.has_key?(options, :preferred_transport)

      # Defaults should be nil
      assert options.include_partial_messages == nil
      assert options.preferred_transport == nil
    end
  end

  describe "Options.new/1 with streaming fields" do
    test "new/1 accepts include_partial_messages keyword" do
      options = Options.new(include_partial_messages: true)
      assert options.include_partial_messages == true
    end

    test "new/1 accepts preferred_transport keyword" do
      options = Options.new(preferred_transport: :control)
      assert options.preferred_transport == :control
    end

    test "new/1 accepts both streaming keywords" do
      options =
        Options.new(
          include_partial_messages: false,
          preferred_transport: :cli
        )

      assert options.include_partial_messages == false
      assert options.preferred_transport == :cli
    end
  end
end
