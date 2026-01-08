defmodule EmailAgent.TestHelpers do
  @moduledoc """
  Helper functions for tests.
  """

  alias EmailAgent.Email

  @doc """
  Builds a test email with optional overrides.
  """
  def build_email(overrides \\ []) do
    defaults = [
      id: "test-#{:erlang.unique_integer([:positive])}",
      message_id: "<test#{:erlang.unique_integer([:positive])}@example.com>",
      from: "sender@example.com",
      from_name: nil,
      to: ["recipient@example.com"],
      cc: [],
      bcc: [],
      reply_to: nil,
      subject: "Test Subject",
      date: DateTime.utc_now(),
      body_text: "Test body content.",
      body_html: nil,
      attachments: [],
      labels: ["inbox"],
      is_read: false,
      is_starred: false,
      raw: nil
    ]

    struct(Email, Keyword.merge(defaults, overrides))
  end

  @doc """
  Creates a temporary database for testing.
  """
  def setup_test_db(context \\ %{}) do
    path = "priv/test_#{:erlang.unique_integer([:positive])}.db"

    on_exit = fn ->
      File.rm(path)
      File.rm(path <> "-shm")
      File.rm(path <> "-wal")
    end

    {:ok, Map.merge(context, %{db_path: path, on_exit: on_exit})}
  end
end
