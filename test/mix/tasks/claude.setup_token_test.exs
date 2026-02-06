defmodule Mix.Tasks.Claude.SetupTokenTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Claude.SetupToken

  test "ensure_auth_manager_started handles successful startup" do
    assert :ok = SetupToken.ensure_auth_manager_started(fn -> {:ok, self()} end)
  end

  test "ensure_auth_manager_started handles already started race" do
    assert :ok =
             SetupToken.ensure_auth_manager_started(fn ->
               {:error, {:already_started, self()}}
             end)
  end

  test "ensure_auth_manager_started returns explicit startup errors" do
    assert {:error, :bad_config} =
             SetupToken.ensure_auth_manager_started(fn -> {:error, :bad_config} end)
  end
end
