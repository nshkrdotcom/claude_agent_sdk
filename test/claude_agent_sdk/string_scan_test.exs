defmodule ClaudeAgentSDK.StringScanTest do
  use ExUnit.Case, async: true

  alias ClaudeAgentSDK.StringScan

  describe "valid_uuid?/1" do
    test "accepts canonical UUID strings" do
      assert StringScan.valid_uuid?("123e4567-e89b-12d3-a456-426614174000")
    end

    test "rejects invalid UUID shapes without pattern matching engines" do
      refute StringScan.valid_uuid?("123e4567-e89b-12d3-a456")
      refute StringScan.valid_uuid?("123e4567-e89b-12d3-a456-42661417400z")
      refute StringScan.valid_uuid?(:session)
    end
  end

  test "extracts the first semantic version from CLI output" do
    assert StringScan.first_semver("claude version 1.2.3 build 9") == "1.2.3"
    assert StringScan.first_semver("no version") == nil
  end

  test "extracts challenge URLs and trims sentence punctuation" do
    assert StringScan.challenge_url("Login at https://anthropic.com/oauth/challenge).") ==
             "https://anthropic.com/oauth/challenge"
  end

  test "normalizes word content for keyword parsing" do
    assert StringScan.words_and_spaces("one,two-three") == "one two three"
  end
end
