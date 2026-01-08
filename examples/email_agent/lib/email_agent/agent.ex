defmodule EmailAgent.Agent do
  @moduledoc """
  AI-powered email agent using the Claude Agent SDK.

  Provides natural language processing for email queries and
  integrates with the Claude Agent SDK for intelligent email
  search and management.

  ## Features

  - Natural language email search
  - Email summarization
  - Smart query parsing
  - Tool-based interactions

  ## Usage

      # Process a query
      {:ok, response} = Agent.process_query("Find emails from John about the project", storage)

      # Build tools for SDK integration
      tools = Agent.build_tools()
  """

  alias ClaudeAgentSDK.Hooks.{Matcher, Output}
  alias EmailAgent.Email
  alias EmailAgent.Storage

  # Dialyzer can't fully trace the complex hooks type from ClaudeAgentSDK
  @dialyzer {:nowarn_function, process_query: 2}

  @doc """
  Processes a natural language query about emails.

  Uses Claude AI to interpret the query and search through stored emails.
  """
  @spec process_query(String.t(), pid()) :: {:ok, String.t()} | {:error, term()}
  def process_query(query, storage) when is_binary(query) and is_pid(storage) do
    # Get some context emails for the AI
    {:ok, recent_emails} = Storage.list_emails(storage, limit: 10)

    prompt = build_search_prompt(query, recent_emails)
    tools = build_tools()

    options = %ClaudeAgentSDK.Options{
      model: "haiku",
      system_prompt: build_system_prompt(),
      max_turns: 3,
      allowed_tools: Enum.map(tools, & &1.name),
      hooks: %{
        pre_tool_use: [create_tool_hook()]
      }
    }

    # Run the query through Claude
    try do
      messages =
        ClaudeAgentSDK.query(prompt, options)
        |> Enum.to_list()

      # Extract the final response
      response =
        messages
        |> Enum.filter(&(&1.type == :assistant))
        |> List.last()
        |> case do
          nil -> "No response generated."
          msg -> ClaudeAgentSDK.ContentExtractor.extract_text(msg)
        end

      {:ok, response}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Builds the search prompt for the AI.
  """
  @spec build_search_prompt(String.t(), [Email.t()]) :: String.t()
  def build_search_prompt(query, context_emails) do
    email_context =
      if context_emails == [] do
        "No emails available in the database."
      else
        Enum.map_join(context_emails, "\n\n", &format_email_summary/1)
      end

    """
    User Query: #{query}

    Recent emails for context:
    #{email_context}

    Please help the user with their email query. Use the available tools to search,
    list, or get specific emails as needed. Provide a helpful, concise response.
    """
  end

  @doc """
  Builds the list of email-related tools for Claude.
  """
  @spec build_tools() :: [map()]
  def build_tools do
    [
      %{
        name: "search_emails",
        description: "Search emails by text query. Searches in subject, body, and sender.",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "The search query text"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "list_emails",
        description: "List emails with optional filters.",
        input_schema: %{
          type: "object",
          properties: %{
            limit: %{
              type: "integer",
              description: "Maximum number of emails to return (default: 10)"
            },
            unread_only: %{
              type: "boolean",
              description: "Only return unread emails"
            },
            label: %{
              type: "string",
              description: "Filter by label"
            }
          }
        }
      },
      %{
        name: "get_email",
        description: "Get a specific email by its ID.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{
              type: "string",
              description: "The email ID"
            }
          },
          required: ["id"]
        }
      },
      %{
        name: "mark_as_read",
        description: "Mark an email as read.",
        input_schema: %{
          type: "object",
          properties: %{
            id: %{
              type: "string",
              description: "The email ID to mark as read"
            }
          },
          required: ["id"]
        }
      }
    ]
  end

  @doc """
  Executes a tool with the given input.
  """
  @spec execute_tool(String.t(), map(), pid()) ::
          {:ok, map()} | {:error, atom()}
  def execute_tool("search_emails", input, storage), do: execute_search_emails(input, storage)
  def execute_tool("list_emails", input, storage), do: execute_list_emails(input, storage)
  def execute_tool("get_email", input, storage), do: execute_get_email(input, storage)
  def execute_tool("mark_as_read", input, storage), do: execute_mark_as_read(input, storage)
  def execute_tool(_tool_name, _input, _storage), do: {:error, :unknown_tool}

  defp execute_search_emails(input, storage) do
    query = Map.get(input, "query", "")

    case Storage.search_emails(storage, query) do
      {:ok, emails} ->
        {:ok,
         %{emails: Enum.map(emails, &email_to_map/1), message: "Found #{length(emails)} emails"}}

      {:error, reason} ->
        {:ok, %{message: "Search failed: #{inspect(reason)}"}}
    end
  end

  defp execute_list_emails(input, storage) do
    opts =
      [
        limit: Map.get(input, "limit", 10),
        unread_only: Map.get(input, "unread_only", false),
        label: Map.get(input, "label")
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Storage.list_emails(storage, opts) do
      {:ok, emails} ->
        {:ok, %{emails: Enum.map(emails, &email_to_map/1)}}

      {:error, reason} ->
        {:ok, %{message: "List failed: #{inspect(reason)}"}}
    end
  end

  defp execute_get_email(input, storage) do
    id = Map.get(input, "id")

    case Storage.get_email(storage, id) do
      {:ok, email} -> {:ok, %{email: email_to_map(email)}}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:ok, %{message: "Get failed: #{inspect(reason)}"}}
    end
  end

  defp execute_mark_as_read(input, storage) do
    id = Map.get(input, "id")

    case Storage.update_email(storage, id, %{is_read: true}) do
      {:ok, _} -> {:ok, %{success: true}}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:ok, %{message: "Update failed: #{inspect(reason)}"}}
    end
  end

  @doc """
  Formats an email for human-readable display.
  """
  @spec format_email_for_display(Email.t()) :: String.t()
  def format_email_for_display(%Email{} = email) do
    sender = Email.sender_display_name(email)
    date = Email.formatted_date(email)

    body_preview =
      (email.body_text || "")
      |> String.trim()
      |> String.slice(0, 500)
      |> case do
        text when byte_size(text) >= 500 -> text <> "..."
        text -> text
      end

    """
    From: #{sender} <#{email.from}>
    Date: #{date}
    Subject: #{email.subject}
    #{if email.is_read, do: "[Read]", else: "[Unread]"} #{if email.is_starred, do: "[Starred]", else: ""}

    #{body_preview}
    """
  end

  @doc """
  Formats a list of emails as search results.
  """
  @spec format_search_results([Email.t()]) :: String.t()
  def format_search_results([]) do
    "No emails found matching your query."
  end

  def format_search_results(emails) do
    count = length(emails)

    results =
      emails
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {email, idx} ->
        sender = Email.sender_display_name(email)
        preview = Email.preview(email) |> String.slice(0, 80)
        read_marker = if email.is_read, do: " ", else: "*"

        "#{idx}. [#{read_marker}] #{sender}: #{email.subject}\n   #{preview}..."
      end)

    "Found #{count} email(s):\n\n#{results}"
  end

  @doc """
  Parses a natural language query into structured filters.
  """
  @spec parse_natural_language_query(String.t()) :: map()
  def parse_natural_language_query(query) do
    query_lower = String.downcase(query)

    %{
      from: extract_from_filter(query_lower),
      keywords: extract_keywords(query_lower),
      date_filter: extract_date_filter(query_lower),
      unread_only: String.contains?(query_lower, "unread"),
      starred_only:
        String.contains?(query_lower, "starred") or String.contains?(query_lower, "important"),
      label: if(String.contains?(query_lower, "important"), do: "important", else: nil)
    }
  end

  defp extract_from_filter(query) do
    case Regex.run(~r/from[:\s]+(\w+)/, query) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp extract_keywords(query) do
    stop_words = ~w(find show me all the emails from about to with in)

    query
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(fn word -> word in stop_words or String.length(word) < 3 end)
  end

  defp extract_date_filter(query) do
    cond do
      String.contains?(query, "last week") ->
        DateTime.add(DateTime.utc_now(), -7, :day)

      String.contains?(query, "this week") ->
        DateTime.add(DateTime.utc_now(), -7, :day)

      String.contains?(query, "today") ->
        DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00])

      String.contains?(query, "yesterday") ->
        DateTime.add(DateTime.utc_now(), -1, :day)

      String.contains?(query, "this month") ->
        DateTime.add(DateTime.utc_now(), -30, :day)

      true ->
        nil
    end
  end

  @doc """
  Builds the system prompt for the email agent.
  """
  @spec build_system_prompt() :: String.t()
  def build_system_prompt do
    """
    You are an intelligent email assistant. You help users search, read, and manage their emails.

    Your capabilities include:
    - Searching emails by keyword, sender, subject, or date
    - Listing recent or filtered emails
    - Summarizing email content
    - Marking emails as read
    - Answering questions about email contents

    When responding:
    - Be concise and helpful
    - If searching for emails, use the search_emails tool
    - For listing emails, use the list_emails tool with appropriate filters
    - Summarize results clearly for the user
    - If no results are found, suggest alternative searches

    Always respect user privacy and only access emails they explicitly ask about.
    """
  end

  @doc """
  Creates a hook callback for tool tracking.
  """
  @spec create_tool_hook() :: Matcher.t()
  def create_tool_hook do
    # Match all tools with wildcard
    Matcher.new("*", [
      fn input, _tool_use_id, _context ->
        tool_name = Map.get(input, "tool_name", "unknown")

        # Log tool usage
        require Logger
        Logger.debug("Email agent tool called: #{tool_name}")

        # Allow all email tools
        Output.allow()
      end
    ])
  end

  # Private helpers

  defp format_email_summary(%Email{} = email) do
    sender = Email.sender_display_name(email)
    preview = Email.preview(email)

    "[#{email.id}] From: #{sender} | Subject: #{email.subject} | Preview: #{preview}"
  end

  defp email_to_map(%Email{} = email) do
    %{
      id: email.id,
      from: email.from,
      from_name: email.from_name,
      to: email.to,
      subject: email.subject,
      date: email.date && DateTime.to_iso8601(email.date),
      body_preview: Email.preview(email),
      is_read: email.is_read,
      is_starred: email.is_starred,
      has_attachments: Email.has_attachments?(email)
    }
  end
end
