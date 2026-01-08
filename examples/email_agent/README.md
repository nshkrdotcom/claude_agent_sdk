# Email Agent

An AI-powered email management application built with the Claude Agent SDK for Elixir.

## Overview

This example demonstrates how to build an intelligent email agent that integrates IMAP email access with Claude AI for natural language email queries and management.

### What This Demonstrates

- **IMAP Integration**: Connecting to email servers via IMAP protocol
- **SQLite Storage**: Local email persistence without Ecto
- **Claude Agent SDK**: AI-powered natural language email search
- **GenServer Patterns**: Process supervision and connection management
- **Automation Rules**: File-based email processing rules

## Architecture

```
+------------------+     +------------------+     +------------------+
|                  |     |                  |     |                  |
|   IMAP Server    |<--->|  IMAP.Connection |<--->|     Storage      |
|   (Gmail, etc)   |     |    GenServer     |     |     (SQLite)     |
|                  |     |                  |     |                  |
+------------------+     +------------------+     +------------------+
                                                          ^
                                                          |
                                                          v
                         +------------------+     +------------------+
                         |                  |     |                  |
                         |   Claude Agent   |<--->|   Rules Engine   |
                         |      (SDK)       |     |     (JSON)       |
                         |                  |     |                  |
                         +------------------+     +------------------+
```

### Key Components

| Module | Description |
|--------|-------------|
| `EmailAgent` | Main API module |
| `EmailAgent.IMAP.Connection` | GenServer for IMAP connection management |
| `EmailAgent.Storage` | SQLite-based email persistence |
| `EmailAgent.Agent` | Claude SDK integration for AI queries |
| `EmailAgent.Rules` | File-based automation rules engine |
| `EmailAgent.EmailParser` | RFC 5322 email parsing |

## Setup

### 1. Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- Claude CLI authenticated (`claude login`)
- Email account with IMAP access

### 2. Installation

```bash
cd examples/email_agent
mix deps.get
```

### 3. Configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```env
# Required
ANTHROPIC_API_KEY=sk-ant-your-api-key
IMAP_HOST=imap.gmail.com
IMAP_PORT=993
EMAIL_ADDRESS=your-email@gmail.com
EMAIL_PASSWORD=your-app-password

# Optional
MAX_EMAILS_TO_FETCH=50
SYNC_INTERVAL_SECONDS=300
```

### Gmail Setup

For Gmail users:

1. **Enable 2-Factor Authentication** on your Google account
2. **Generate an App Password**:
   - Go to [Google Account Security](https://myaccount.google.com/security)
   - Under "2-Step Verification", click "App passwords"
   - Generate a new password for "Mail"
3. **Use the 16-character App Password** (not your regular password)

## Usage

### Starting the Application

```bash
# Start with IEx shell
iex -S mix

# Or run in production mode
MIX_ENV=prod mix run --no-halt
```

### Basic Operations

```elixir
# Sync emails from IMAP server
EmailAgent.sync_emails()

# List recent emails
{:ok, emails} = EmailAgent.list_emails(limit: 10)

# Search emails
{:ok, results} = EmailAgent.search("quarterly report")

# Ask Claude about your emails
{:ok, response} = EmailAgent.ask("Find emails from John about the project")

# Apply automation rules
{:ok, processed_count} = EmailAgent.apply_rules()
```

### AI-Powered Queries

The agent understands natural language:

```elixir
EmailAgent.ask("What are my unread emails about?")
EmailAgent.ask("Summarize emails from last week")
EmailAgent.ask("Find important emails with attachments")
EmailAgent.ask("Which emails need a response?")
```

### Automation Rules

Rules are defined in `priv/rules.json`:

```json
{
  "rules": [
    {
      "name": "Label newsletters",
      "condition": {
        "from_contains": "newsletter"
      },
      "action": {
        "type": "label",
        "label": "newsletters"
      }
    },
    {
      "name": "Star urgent emails",
      "condition": {
        "subject_contains": "urgent"
      },
      "action": {
        "type": "star"
      }
    }
  ]
}
```

#### Condition Types

- `from_contains`: Sender address contains string
- `subject_contains`: Subject contains string
- `has_attachment`: Email has attachments (boolean)
- `older_than_days`: Email is older than N days

#### Action Types

- `label`: Add a label to the email
- `move`: Move to a folder
- `mark_read`: Mark as read
- `star`: Star the email

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Run specific test file
mix test test/email_agent/storage_test.exs
```

## Security Considerations

**This is a demonstration application for local development only.**

### Security Notes

1. **Credentials Storage**: Credentials are stored in plain text in `.env` files
2. **No Authentication**: The application has no user authentication
3. **Local Only**: Not designed for production deployment
4. **Database Security**: SQLite database is unencrypted

### Best Practices

- Never commit `.env` files to version control
- Use app-specific passwords (not your main password)
- Run only on trusted networks
- Delete the database when done testing

## Project Structure

```
email_agent/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   └── prod.exs
├── lib/
│   └── email_agent/
│       ├── application.ex      # OTP Application
│       ├── agent.ex            # Claude SDK integration
│       ├── email.ex            # Email struct
│       ├── email_parser.ex     # RFC 5322 parsing
│       ├── rules.ex            # Automation engine
│       ├── storage.ex          # SQLite storage
│       └── imap/
│           ├── client.ex       # Real IMAP client
│           ├── connection.ex   # GenServer
│           └── connection_behaviour.ex
├── priv/
│   └── rules.json              # Automation rules
├── test/
│   ├── email_agent/
│   │   ├── agent_test.exs
│   │   ├── email_parser_test.exs
│   │   ├── rules_test.exs
│   │   ├── storage_test.exs
│   │   └── imap/
│   │       └── connection_test.exs
│   └── test_helper.exs
├── .env.example
├── .gitignore
├── mix.exs
└── README.md
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `claude_agent_sdk` | Claude AI integration |
| `mail` | IMAP protocol support |
| `exqlite` | SQLite database |
| `dotenvy` | Environment variable loading |
| `mox` | Test mocking |
| `credo` | Code analysis |
| `dialyxir` | Type checking |

## Troubleshooting

### Connection Issues

```elixir
# Check if IMAP is configured
System.get_env("IMAP_HOST")

# Start in storage-only mode
# (Just don't set IMAP environment variables)
```

### Gmail Authentication Errors

- Ensure 2FA is enabled
- Use App Password, not regular password
- Check for spaces in the password

### Database Issues

```bash
# Reset the database
mix db.reset
```

## Reference

This example is inspired by the [claude-agent-sdk-demos/email-agent](https://github.com/anthropics/claude-agent-sdk-demos/tree/main/email-agent) TypeScript demo.

## License

MIT License - See the main Claude Agent SDK repository for details.
