# Phoenix Chat - Claude Agent SDK Demo

A real-time chat application demonstrating the Claude Agent SDK with Phoenix LiveView and WebSocket channels.

## What This Demonstrates

This example showcases:

- **Phoenix LiveView Integration** - Real-time UI updates without writing JavaScript
- **WebSocket Streaming** - Live streaming of Claude responses via Phoenix Channels
- **GenServer Architecture** - Elixir/OTP patterns for session and state management
- **Claude Agent SDK** - Integration with the Elixir SDK for AI-powered conversations
- **Tool Usage Display** - Real-time visualization of Claude's tool invocations

## Architecture

```
+------------------+     +----------------------+     +------------------+
|     Browser      |<--->|   Phoenix Server     |<--->|  Claude Agent    |
|  (LiveView UI)   |     |  (LiveView/Channel)  |     |      SDK         |
+------------------+     +----------------------+     +------------------+
        |                         |
        |   WebSocket             |
        +-------------------------+
                                  |
                           +------+------+
                           |             |
                      +----+----+   +----+----+
                      |ChatStore|   |Session  |
                      |(Memory) |   |Registry |
                      +---------+   +---------+
```

### Components

| Component | Description |
|-----------|-------------|
| `ChatLive` | Phoenix LiveView for the chat UI |
| `ChatChannel` | Phoenix Channel for WebSocket streaming |
| `ChatStore` | GenServer for in-memory chat/message storage |
| `ChatSession` | GenServer managing Claude agent sessions |
| `SessionRegistry` | DynamicSupervisor for session lifecycle |

## Prerequisites

- Elixir 1.15+
- Claude CLI authenticated (`claude login`)
- Phoenix 1.7+

## Installation

```bash
# Navigate to the example directory
cd examples/phoenix_chat

# Install dependencies
mix deps.get

# Start the server
mix phx.server
```

Open http://localhost:4000 in your browser.

## Usage

1. **Create a Chat** - Click "New Chat" in the sidebar
2. **Send Messages** - Type in the input box and press Enter or click Send
3. **Watch Streaming** - See Claude's response appear in real-time
4. **View Tool Usage** - Tool invocations are displayed inline as expandable blocks
5. **Multiple Chats** - Create multiple chats and switch between them

## Project Structure

```
phoenix_chat/
+-- config/
|   +-- config.exs           # Main configuration
|   +-- dev.exs              # Development settings
|   +-- test.exs             # Test settings
|   +-- prod.exs             # Production settings
+-- lib/
|   +-- phoenix_chat/
|   |   +-- application.ex   # OTP Application
|   |   +-- chat_store.ex    # In-memory storage GenServer
|   |   +-- chat_session.ex  # Claude session GenServer
|   |   +-- session_registry.ex  # Session supervisor
|   +-- phoenix_chat_web/
|   |   +-- channels/
|   |   |   +-- chat_channel.ex  # WebSocket channel
|   |   |   +-- user_socket.ex   # Socket handler
|   |   +-- controllers/
|   |   |   +-- chat_controller.ex  # REST API
|   |   +-- live/
|   |   |   +-- chat_live.ex     # Main LiveView
|   |   +-- components/
|   |   |   +-- core_components.ex  # UI components
|   |   |   +-- layouts/         # Layout templates
|   |   +-- router.ex            # Routes
|   |   +-- endpoint.ex          # HTTP endpoint
+-- test/
|   +-- phoenix_chat/
|   |   +-- chat_store_test.exs
|   |   +-- chat_session_test.exs
|   +-- phoenix_chat_web/
|   |   +-- channels/
|   |   |   +-- chat_channel_test.exs
|   |   +-- live/
|   |   |   +-- chat_live_test.exs
+-- priv/
|   +-- static/
|       +-- assets/
|           +-- app.js           # Frontend JavaScript
```

## API Endpoints

### REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/chats` | List all chats |
| POST | `/api/chats` | Create new chat |
| GET | `/api/chats/:id` | Get chat details |
| DELETE | `/api/chats/:id` | Delete chat |
| GET | `/api/chats/:id/messages` | Get chat messages |

### WebSocket (via LiveView)

The chat UI uses Phoenix LiveView for real-time updates. No separate WebSocket connection is needed for the UI.

For programmatic access, connect to `/socket/websocket` and join a channel:

```javascript
// Subscribe to a chat
socket.channel("chat:lobby").push("subscribe", {chat_id: "..."})

// Send a message
socket.channel("chat:lobby").push("chat", {chat_id: "...", content: "Hello!"})
```

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/phoenix_chat/chat_store_test.exs
```

## Quality Checks

```bash
# Format code
mix format

# Run Credo static analysis
mix credo --strict

# Run Dialyzer type checking
mix dialyzer
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Phoenix secret key (prod only) | - |
| `PHX_HOST` | Hostname for production | `localhost` |
| `PORT` | HTTP port | `4000` |

### Claude SDK Options

Configure Claude options in `lib/phoenix_chat/chat_session.ex`:

```elixir
%ClaudeAgentSDK.Options{
  max_turns: 100,           # Max conversation turns
  model: "sonnet",          # Claude model
  permission_mode: :bypass_permissions,
  allowed_tools: [
    "Bash", "Read", "Write", "Edit",
    "Glob", "Grep", "WebSearch", "WebFetch"
  ]
}
```

## Production Considerations

This is a demonstration application. For production use, consider:

1. **Persistent Storage** - Replace `ChatStore` with a database (PostgreSQL, etc.)
2. **Authentication** - Add user authentication and authorization
3. **Rate Limiting** - Implement rate limiting for API and WebSocket
4. **Error Handling** - Add comprehensive error handling and monitoring
5. **Session Persistence** - Store Claude session transcripts for resumption

## Comparison with TypeScript Demo

This implementation mirrors the TypeScript `simple-chatapp` demo:

| TypeScript | Elixir |
|------------|--------|
| `Session` class | `ChatSession` GenServer |
| `ChatStore` class | `ChatStore` GenServer |
| `MessageQueue` | GenServer state + Task |
| Express routes | Phoenix controllers |
| WebSocket (ws) | Phoenix Channels |
| React components | LiveView + HEEx |

## License

Same as the parent Claude Agent SDK project.
