defmodule EmailAgent.AgentTest do
  use ExUnit.Case, async: true

  alias EmailAgent.Agent
  alias EmailAgent.Email

  describe "build_search_prompt/2" do
    test "builds prompt for email search query" do
      query = "find emails from John about the project"

      prompt = Agent.build_search_prompt(query, [])

      assert prompt =~ query
      assert prompt =~ "search"
      assert prompt =~ "email"
    end

    test "includes email context in prompt" do
      query = "summarize this"

      emails = [
        build_email(subject: "Project Update", body_text: "The project is on track."),
        build_email(subject: "Meeting Notes", body_text: "We discussed the timeline.")
      ]

      prompt = Agent.build_search_prompt(query, emails)

      assert prompt =~ "Project Update"
      assert prompt =~ "Meeting Notes"
    end
  end

  describe "build_tools/0" do
    test "returns list of email-related tools" do
      tools = Agent.build_tools()

      assert is_list(tools)

      tool_names = Enum.map(tools, & &1.name)

      assert "search_emails" in tool_names
      assert "get_email" in tool_names
      assert "list_emails" in tool_names
      assert "mark_as_read" in tool_names
    end

    test "each tool has required metadata" do
      tools = Agent.build_tools()

      for tool <- tools do
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :description)
        assert Map.has_key?(tool, :input_schema)
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.input_schema)
      end
    end
  end

  describe "execute_tool/3" do
    setup do
      # Use a real storage for integration tests
      db_path = "priv/test_agent_#{:erlang.unique_integer([:positive])}.db"
      File.rm(db_path)
      {:ok, conn} = EmailAgent.Storage.init_db(database_path: db_path)
      {:ok, pid} = EmailAgent.Storage.start_link(database_path: db_path, name: nil)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        EmailAgent.Storage.close(conn)
        File.rm(db_path)
      end)

      {:ok, storage: pid}
    end

    test "executes search_emails tool", %{storage: storage} do
      result = Agent.execute_tool("search_emails", %{"query" => "meeting"}, storage)

      assert {:ok, response} = result
      assert is_list(response.emails) || is_binary(response.message)
    end

    test "executes get_email tool", %{storage: storage} do
      result = Agent.execute_tool("get_email", %{"id" => "test-id"}, storage)

      # Not found is expected since no emails inserted
      assert {:error, :not_found} = result
    end

    test "executes list_emails tool with filters", %{storage: storage} do
      result =
        Agent.execute_tool(
          "list_emails",
          %{"limit" => 10, "unread_only" => true},
          storage
        )

      assert {:ok, response} = result
      assert Map.has_key?(response, :emails)
    end

    test "executes mark_as_read tool returns not_found for missing email", %{storage: storage} do
      result = Agent.execute_tool("mark_as_read", %{"id" => "test-id"}, storage)

      assert {:error, :not_found} = result
    end

    test "returns error for unknown tool", %{storage: storage} do
      result = Agent.execute_tool("unknown_tool", %{}, storage)

      assert {:error, :unknown_tool} = result
    end
  end

  describe "format_email_for_display/1" do
    test "formats email for human-readable display" do
      email =
        build_email(
          from: "sender@example.com",
          from_name: "John Doe",
          subject: "Important Update",
          date: ~U[2025-01-06 10:30:00Z],
          body_text: "Hello, this is an important update."
        )

      formatted = Agent.format_email_for_display(email)

      assert formatted =~ "John Doe"
      assert formatted =~ "sender@example.com"
      assert formatted =~ "Important Update"
      assert formatted =~ "important update"
    end

    test "truncates long body text" do
      long_body = String.duplicate("x", 1000)

      email = build_email(body_text: long_body)

      formatted = Agent.format_email_for_display(email)

      # Should be truncated
      assert String.length(formatted) < 1500
      assert formatted =~ "..."
    end
  end

  describe "format_search_results/1" do
    test "formats list of emails as search results" do
      emails = [
        build_email(subject: "Email 1", from: "a@example.com"),
        build_email(subject: "Email 2", from: "b@example.com")
      ]

      formatted = Agent.format_search_results(emails)

      assert formatted =~ "Email 1"
      assert formatted =~ "Email 2"
      assert formatted =~ "a@example.com"
      assert formatted =~ "b@example.com"
    end

    test "returns message for empty results" do
      formatted = Agent.format_search_results([])

      assert formatted =~ "No emails found"
    end

    test "includes match count" do
      emails =
        for i <- 1..5 do
          build_email(subject: "Email #{i}")
        end

      formatted = Agent.format_search_results(emails)

      assert formatted =~ "5"
    end
  end

  describe "parse_natural_language_query/1" do
    test "extracts search terms from natural language" do
      query = "find all emails from john about the quarterly report"

      parsed = Agent.parse_natural_language_query(query)

      assert parsed.from =~ "john"
      assert "quarterly" in parsed.keywords or "report" in parsed.keywords
    end

    test "handles date references" do
      query = "emails from last week"

      parsed = Agent.parse_natural_language_query(query)

      assert parsed.date_filter != nil
    end

    test "handles unread filter" do
      query = "show me unread emails"

      parsed = Agent.parse_natural_language_query(query)

      assert parsed.unread_only == true
    end

    test "handles starred/important filter" do
      query = "important emails from this month"

      parsed = Agent.parse_natural_language_query(query)

      assert parsed.starred_only == true or parsed.label == "important"
    end
  end

  describe "build_system_prompt/0" do
    test "returns comprehensive system prompt" do
      prompt = Agent.build_system_prompt()

      assert is_binary(prompt)
      assert String.length(prompt) > 100

      # Should explain the agent's capabilities
      assert prompt =~ "email"
      assert prompt =~ "search" or prompt =~ "find"
    end
  end

  describe "tool hook integration" do
    test "creates hook callback for tool tracking" do
      matcher = Agent.create_tool_hook()

      # Should return a Matcher struct
      assert %ClaudeAgentSDK.Hooks.Matcher{} = matcher
      assert matcher.matcher == "*"
      assert is_list(matcher.hooks)
      assert length(matcher.hooks) == 1

      # Get the hook function from the matcher
      [hook] = matcher.hooks
      assert is_function(hook, 3)

      # Simulate tool invocation
      input = %{"tool_name" => "search_emails", "tool_input" => %{"query" => "test"}}
      result = hook.(input, "tool_use_123", %{})

      # Hook should return an allow decision (matches SDK Output format)
      assert is_map(result)
      assert result.hookSpecificOutput.permissionDecision == "allow"
    end
  end

  # Helper functions

  defp build_email(overrides) do
    defaults = [
      id: "test-#{:erlang.unique_integer([:positive])}",
      message_id: "<test@example.com>",
      from: "sender@example.com",
      from_name: nil,
      to: ["recipient@example.com"],
      cc: [],
      bcc: [],
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
end
