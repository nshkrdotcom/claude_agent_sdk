defmodule EmailAgent.IMAP.ConnectionBehaviour do
  @moduledoc """
  Behaviour defining the IMAP client interface.

  This behaviour allows for mocking the IMAP client in tests
  while using a real implementation in production.
  """

  @type socket :: term()
  @type uid :: non_neg_integer()

  @callback connect(String.t(), non_neg_integer(), keyword()) ::
              {:ok, socket()} | {:error, term()}

  @callback login(socket(), String.t(), String.t()) ::
              {:ok, term()} | {:error, term()}

  @callback logout(socket()) :: :ok | {:error, term()}

  @callback close(socket()) :: :ok | {:error, term()}

  @callback list_mailboxes(socket()) ::
              {:ok, [String.t()]} | {:error, term()}

  @callback select_mailbox(socket(), String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback search(socket(), term()) ::
              {:ok, [uid()]} | {:error, term()}

  @callback fetch_messages(socket(), list() | Range.t(), keyword()) ::
              {:ok, [String.t()]} | {:error, term()}

  @callback fetch_by_uid(socket(), uid(), keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback store_flags(socket(), uid(), :add | :remove, [atom()]) ::
              :ok | {:error, term()}

  @callback copy(socket(), uid(), String.t()) ::
              {:ok, uid()} | {:error, term()}

  @callback expunge(socket()) :: :ok | {:error, term()}
end
