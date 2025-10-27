# Phoenix LiveView Integration Pattern (v0.6.0)
#
# This demonstrates the recommended pattern for integrating Claude streaming
# with Phoenix LiveView to create real-time AI chat interfaces.
#
# NOTE: This is a pattern/pseudo-code example showing the structure.
# Adapt it for your own Phoenix LiveView application.

defmodule MyAppWeb.ClaudeChatLive do
  @moduledoc """
  LiveView implementation showing streaming Claude responses with hooks.

  Features:
  - Real-time typewriter effect in the UI
  - Security hooks for tool validation
  - Streaming text updates via LiveView
  - Clean resource management
  """

  use Phoenix.LiveView

  alias ClaudeAgentSDK.{Streaming, Options}
  alias ClaudeAgentSDK.Streaming.EventAdapter
  alias ClaudeAgentSDK.Hooks.{Matcher, Output}

  @impl true
  def mount(_params, _session, socket) do
    # Configure streaming with security hooks
    options = %Options{
      allowed_tools: ["Read", "Bash"],
      hooks: %{
        pre_tool_use: [
          Matcher.new("Bash", [&validate_bash/3])
        ]
      }
    }

    # Start streaming session (automatically uses control client)
    {:ok, session} = Streaming.start_session(options)

    socket =
      socket
      |> assign(:session, session)
      |> assign(:messages, [])
      |> assign(:streaming_text, "")
      |> assign(:is_streaming, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => user_message}, socket) do
    # Add user message to chat
    messages = [{:user, user_message} | socket.assigns.messages]

    # Start streaming Claude's response in a task
    pid = self()

    Task.start(fn ->
      Streaming.send_message(socket.assigns.session, user_message)
      |> Stream.each(fn event ->
        send(pid, {:claude_event, event})
      end)
      |> Stream.run()
    end)

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:streaming_text, "")
      |> assign(:is_streaming, true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_event, %{type: :text_delta, text: text}}, socket) do
    # Update streaming text in real-time
    new_text = socket.assigns.streaming_text <> text

    socket = assign(socket, :streaming_text, new_text)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_event, %{type: :message_stop}}, socket) do
    # Stream complete, add to messages
    messages = [{:assistant, socket.assigns.streaming_text} | socket.assigns.messages]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:streaming_text, "")
      |> assign(:is_streaming, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claude_event, _other_event}, socket) do
    # Handle other events (tool execution, thinking, etc.)
    # Could display tool usage indicators, thinking status, etc.
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Clean up streaming session when LiveView closes
    if socket.assigns[:session] do
      Streaming.close_session(socket.assigns.session)
    end

    :ok
  end

  # Private functions

  defp validate_bash(input, _tool_use_id, _context) do
    command = input["tool_input"]["command"]

    if safe_command?(command) do
      Output.allow()
    else
      Output.deny("Command not permitted for security reasons")
    end
  end

  defp safe_command?(cmd) do
    dangerous = ["rm -rf", "sudo", "chmod 777", ":(){:|:&};:"]
    not Enum.any?(dangerous, &String.contains?(cmd, &1))
  end

  # Template rendering
  def render(assigns) do
    ~H"""
    <div class="claude-chat">
      <div class="messages">
        <%= for {role, content} <- Enum.reverse(@messages) do %>
          <div class={"message message-#{role}"}>
            <div class="role"><%= role %></div>
            <div class="content"><%= content %></div>
          </div>
        <% end %>

        <%= if @is_streaming do %>
          <div class="message message-assistant streaming">
            <div class="role">assistant</div>
            <div class="content">
              <%= @streaming_text %>
              <span class="cursor">|</span>
            </div>
          </div>
        <% end %>
      </div>

      <form phx-submit="send_message">
        <input
          type="text"
          name="message"
          placeholder="Ask Claude..."
          disabled={@is_streaming}
        />
        <button type="submit" disabled={@is_streaming}>
          <%= if @is_streaming, do: "Streaming...", else: "Send" %>
        </button>
      </form>
    </div>
    """
  end
end

# Usage Notes:
#
# 1. Add to your router:
#    live "/chat", MyAppWeb.ClaudeChatLive
#
# 2. Add CSS for styling:
#    .message { padding: 1rem; margin: 0.5rem 0; border-radius: 8px; }
#    .message-user { background: #e3f2fd; }
#    .message-assistant { background: #f5f5f5; }
#    .message.streaming .cursor { animation: blink 1s infinite; }
#
# 3. Ensure Claude CLI is authenticated:
#    claude --version
#
# 4. Start your Phoenix app:
#    mix phx.server
