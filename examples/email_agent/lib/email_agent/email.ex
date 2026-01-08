defmodule EmailAgent.Email do
  @moduledoc """
  Struct representing a parsed email message.

  Contains all relevant email metadata and content extracted
  from raw RFC 5322 email format.
  """

  @typedoc """
  Email attachment metadata.
  """
  @type attachment :: %{
          filename: String.t(),
          content_type: String.t(),
          size: non_neg_integer() | nil,
          content_id: String.t() | nil
        }

  @typedoc """
  Complete email structure.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          message_id: String.t() | nil,
          from: String.t(),
          from_name: String.t() | nil,
          to: [String.t()],
          cc: [String.t()],
          bcc: [String.t()],
          reply_to: String.t() | nil,
          subject: String.t(),
          date: DateTime.t() | nil,
          body_text: String.t() | nil,
          body_html: String.t() | nil,
          attachments: [attachment()],
          labels: [String.t()],
          is_read: boolean(),
          is_starred: boolean(),
          raw: String.t() | nil
        }

  defstruct [
    :id,
    :message_id,
    :from,
    :from_name,
    :to,
    :cc,
    :bcc,
    :reply_to,
    :subject,
    :date,
    :body_text,
    :body_html,
    :attachments,
    :labels,
    :is_read,
    :is_starred,
    :raw
  ]

  @doc """
  Creates a new Email struct with default values.
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) do
    defaults = %{
      id: nil,
      message_id: nil,
      from: "",
      from_name: nil,
      to: [],
      cc: [],
      bcc: [],
      reply_to: nil,
      subject: "",
      date: nil,
      body_text: nil,
      body_html: nil,
      attachments: [],
      labels: [],
      is_read: false,
      is_starred: false,
      raw: nil
    }

    struct(__MODULE__, Map.merge(defaults, attrs))
  end

  @doc """
  Returns a preview of the email body (first 200 characters).
  """
  @spec preview(t()) :: String.t()
  def preview(%__MODULE__{body_text: nil}), do: ""

  def preview(%__MODULE__{body_text: text}) do
    text
    |> String.trim()
    |> String.slice(0, 200)
  end

  @doc """
  Checks if the email has any attachments.
  """
  @spec has_attachments?(t()) :: boolean()
  def has_attachments?(%__MODULE__{attachments: attachments}) do
    attachments != [] and attachments != nil
  end

  @doc """
  Returns the display name for the sender.

  Uses from_name if available, otherwise uses the email address.
  """
  @spec sender_display_name(t()) :: String.t()
  def sender_display_name(%__MODULE__{from_name: nil, from: from}), do: from
  def sender_display_name(%__MODULE__{from_name: name}), do: name

  @doc """
  Formats the email date for display.
  """
  @spec formatted_date(t()) :: String.t()
  def formatted_date(%__MODULE__{date: nil}), do: "Unknown date"

  def formatted_date(%__MODULE__{date: date}) do
    Calendar.strftime(date, "%b %d, %Y %I:%M %p")
  end
end
