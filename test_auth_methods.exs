#!/usr/bin/env elixir

# Automated test of all 3 authentication methods
# Tests each method programmatically with the Claude CLI

IO.puts("🔍 Testing All Authentication Methods")
IO.puts("=" |> String.duplicate(70))
IO.puts("")

# Disable mocking
Application.put_env(:claude_agent_sdk, :use_mock, false)

# Test helper function
defmodule AuthTester do
  def test_cli_with_env(env_vars) do
    # Test Claude CLI directly with specific env vars
    case System.cmd(
           "claude",
           ["--print", "Say: Auth test", "--output-format", "json", "--max-turns", "1"],
           stderr_to_stdout: true,
           env: env_vars
         ) do
      {output, 0} ->
        cond do
          String.contains?(output, "authentication_error") or
              String.contains?(output, "Invalid bearer token") ->
            {:error, :auth_failed}

          String.contains?(output, "Auth test") or String.contains?(output, "message") ->
            {:ok, :authenticated}

          true ->
            {:unknown, output}
        end

      {error, _code} ->
        {:error, error}
    end
  end

  def test_via_sdk do
    # Test through SDK
    try do
      result =
        ClaudeAgentSDK.query("Say: SDK test", %ClaudeAgentSDK.Options{max_turns: 1})
        |> Enum.to_list()

      assistant_msg = Enum.find(result, &(&1.type == :assistant))

      if assistant_msg do
        response = ClaudeAgentSDK.ContentExtractor.extract_text(assistant_msg)

        cond do
          String.contains?(response, "authentication_error") or
              String.contains?(response, "Invalid bearer token") ->
            {:error, :auth_failed}

          String.contains?(response, "SDK test") or String.length(response) > 0 ->
            {:ok, :authenticated}

          true ->
            {:unknown, response}
        end
      else
        {:error, :no_response}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end

# ============================================================================
# METHOD 1: Existing claude login session
# ============================================================================

IO.puts("METHOD 1: Existing `claude login` Session")
IO.puts("─" |> String.duplicate(70))

# Clear env vars to test pure session
env_clean = [
  {"PATH", System.get_env("PATH")},
  {"HOME", System.get_env("HOME")}
]

case AuthTester.test_cli_with_env(env_clean) do
  {:ok, :authenticated} ->
    IO.puts("   ✅ PASS: CLI can use stored session from 'claude login'")

  {:error, :auth_failed} ->
    IO.puts("   ❌ FAIL: No valid 'claude login' session found")
    IO.puts("   (This is OK if you haven't run 'claude login')")

  {:error, reason} ->
    IO.puts("   ❌ ERROR: #{reason}")

  {:unknown, output} ->
    IO.puts("   ⚠️  UNKNOWN: Got output but couldn't determine auth status")
    IO.puts("   Output preview: #{String.slice(output, 0, 200)}")
end

IO.puts("")

# ============================================================================
# METHOD 2: CLAUDE_AGENT_OAUTH_TOKEN
# ============================================================================

IO.puts("METHOD 2: CLAUDE_AGENT_OAUTH_TOKEN Environment Variable")
IO.puts("─" |> String.duplicate(70))

oauth_token = System.get_env("CLAUDE_AGENT_OAUTH_TOKEN")

if oauth_token do
  IO.puts("   Token found: #{String.slice(oauth_token, 0, 30)}...")

  env_with_oauth = [
    {"CLAUDE_AGENT_OAUTH_TOKEN", oauth_token},
    {"PATH", System.get_env("PATH")},
    {"HOME", System.get_env("HOME")}
  ]

  case AuthTester.test_cli_with_env(env_with_oauth) do
    {:ok, :authenticated} ->
      IO.puts("   ✅ PASS: CLI accepts CLAUDE_AGENT_OAUTH_TOKEN")

    {:error, :auth_failed} ->
      IO.puts("   ❌ FAIL: CLI doesn't recognize CLAUDE_AGENT_OAUTH_TOKEN")
      IO.puts("   Note: CLI may require ANTHROPIC_API_KEY instead")

    {:error, reason} ->
      IO.puts("   ❌ ERROR: #{reason}")

    {:unknown, output} ->
      IO.puts("   ⚠️  UNKNOWN")
      IO.puts("   Output: #{String.slice(output, 0, 200)}")
  end
else
  IO.puts("   ⚠️  SKIP: CLAUDE_AGENT_OAUTH_TOKEN not set")
  IO.puts("   Set with: export CLAUDE_AGENT_OAUTH_TOKEN='sk-ant-oat01-...'")
end

IO.puts("")

# ============================================================================
# METHOD 3: ANTHROPIC_API_KEY (with OAuth token value)
# ============================================================================

IO.puts("METHOD 3: ANTHROPIC_API_KEY with OAuth Token")
IO.puts("─" |> String.duplicate(70))

if oauth_token do
  IO.puts("   Testing if CLI accepts OAuth token as ANTHROPIC_API_KEY...")

  env_with_api_key = [
    {"ANTHROPIC_API_KEY", oauth_token},
    {"PATH", System.get_env("PATH")},
    {"HOME", System.get_env("HOME")}
  ]

  case AuthTester.test_cli_with_env(env_with_api_key) do
    {:ok, :authenticated} ->
      IO.puts("   ✅ PASS: CLI accepts OAuth token via ANTHROPIC_API_KEY")
      IO.puts("   💡 RECOMMENDATION: Use ANTHROPIC_API_KEY for OAuth tokens")

    {:error, :auth_failed} ->
      IO.puts("   ❌ FAIL: OAuth token not accepted as ANTHROPIC_API_KEY")

    {:error, reason} ->
      IO.puts("   ❌ ERROR: #{reason}")

    {:unknown, output} ->
      IO.puts("   ⚠️  UNKNOWN")
  end
else
  IO.puts("   ⚠️  SKIP: No OAuth token available for testing")
end

IO.puts("")

# ============================================================================
# METHOD 4: SDK Integration Test
# ============================================================================

IO.puts("METHOD 4: SDK Integration (with current environment)")
IO.puts("─" |> String.duplicate(70))

IO.puts("   Current environment:")
IO.puts("   • CLAUDE_AGENT_OAUTH_TOKEN: #{if oauth_token, do: "SET", else: "NOT SET"}")

IO.puts(
  "   • ANTHROPIC_API_KEY: #{if System.get_env("ANTHROPIC_API_KEY"), do: "SET", else: "NOT SET"}"
)

IO.puts("")

case AuthTester.test_via_sdk() do
  {:ok, :authenticated} ->
    IO.puts("   ✅ PASS: SDK authentication working!")

  {:error, :auth_failed} ->
    IO.puts("   ❌ FAIL: SDK cannot authenticate")
    IO.puts("   Check that environment variables are being passed to subprocess")

  {:error, reason} ->
    IO.puts("   ❌ ERROR: #{reason}")

  {:unknown, response} ->
    IO.puts("   ⚠️  UNKNOWN: #{response}")
end

IO.puts("")

# ============================================================================
# SUMMARY & RECOMMENDATIONS
# ============================================================================

IO.puts("=" |> String.duplicate(70))
IO.puts("SUMMARY & RECOMMENDATIONS")
IO.puts("=" |> String.duplicate(70))
IO.puts("")

IO.puts("If METHOD 2 or 3 passed:")
IO.puts("  → SDK is now fixed to pass environment variables to subprocess")
IO.puts("")

IO.puts("If only METHOD 1 passed:")
IO.puts("  → You need to run 'claude login' for SDK to work")
IO.puts("  → OAuth token env vars not working with CLI")
IO.puts("")

IO.puts("Next: Run 'mix run test_live_v0_1_0.exs' to test full feature set")
