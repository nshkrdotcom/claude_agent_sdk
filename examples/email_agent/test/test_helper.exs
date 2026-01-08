ExUnit.start()

# Configure Mox for mocking
Mox.defmock(EmailAgent.IMAP.ConnectionMock, for: EmailAgent.IMAP.ConnectionBehaviour)

# Ensure test database is used
Application.put_env(:email_agent, :database_path, "priv/test_emails.db")
