defmodule ClaudeAgentSDK.TransportTest do
  @moduledoc """
  Tests for Transport behaviour definition.

  Following TDD approach - these tests verify the behaviour callbacks
  are properly defined (RED phase).
  """
  use ClaudeAgentSDK.SupertesterCase

  alias ClaudeAgentSDK.Transport

  describe "behaviour callbacks" do
    test "should_define_start_link_callback_with_arity_1" do
      assert function_exported?(Transport, :behaviour_info, 1)
      callbacks = Transport.behaviour_info(:callbacks)
      assert {:start_link, 1} in callbacks
    end

    test "should_define_send_callback_with_arity_2" do
      callbacks = Transport.behaviour_info(:callbacks)
      assert {:send, 2} in callbacks
    end

    test "should_define_subscribe_callback_with_arity_2" do
      callbacks = Transport.behaviour_info(:callbacks)
      assert {:subscribe, 2} in callbacks
    end

    test "should_define_close_callback_with_arity_1" do
      callbacks = Transport.behaviour_info(:callbacks)
      assert {:close, 1} in callbacks
    end

    test "should_define_status_callback_with_arity_1" do
      callbacks = Transport.behaviour_info(:callbacks)
      assert {:status, 1} in callbacks
    end
  end
end
