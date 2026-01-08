defmodule ResearchAgent.OutputManagerTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.OutputManager

  @output_dir Path.join(
                System.tmp_dir!(),
                "research_agent_test_#{System.unique_integer([:positive])}"
              )

  setup do
    File.mkdir_p!(@output_dir)
    on_exit(fn -> File.rm_rf!(@output_dir) end)
    :ok
  end

  describe "ensure_session_dir/2" do
    test "creates a session directory" do
      {:ok, path} = OutputManager.ensure_session_dir(@output_dir, "session_abc")

      assert File.dir?(path)
      assert String.contains?(path, "session_abc")
    end

    test "returns the same path if called multiple times" do
      {:ok, path1} = OutputManager.ensure_session_dir(@output_dir, "session_xyz")
      {:ok, path2} = OutputManager.ensure_session_dir(@output_dir, "session_xyz")

      assert path1 == path2
    end
  end

  describe "write_research_notes/3" do
    test "writes research notes to a file" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "notes_session")

      notes = """
      # Research Notes: AI Safety

      ## Key Findings
      1. Finding one
      2. Finding two
      """

      {:ok, path} = OutputManager.write_research_notes(session_dir, "ai_safety", notes)

      assert File.exists?(path)
      assert File.read!(path) == notes
      assert String.ends_with?(path, ".md")
    end

    test "sanitizes topic names for filenames" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "sanitize_session")

      notes = "Test notes"
      {:ok, path} = OutputManager.write_research_notes(session_dir, "AI/Safety: Test?", notes)

      refute String.contains?(path, "/Safety")
      refute String.contains?(path, "?")
    end
  end

  describe "write_report/3" do
    test "writes a final report to a file" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "report_session")

      report = """
      # Research Report: Quantum Computing

      ## Executive Summary
      This report covers...
      """

      {:ok, path} = OutputManager.write_report(session_dir, "quantum_computing", report)

      assert File.exists?(path)
      assert String.contains?(path, "report")
      assert String.ends_with?(path, ".md")
    end
  end

  describe "write_structured_data/3" do
    test "writes JSON data to a file" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "data_session")

      data = %{
        topic: "AI",
        sources: ["source1", "source2"],
        metrics: %{accuracy: 0.95}
      }

      {:ok, path} = OutputManager.write_structured_data(session_dir, "analysis_results", data)

      assert File.exists?(path)
      assert String.ends_with?(path, ".json")

      {:ok, content} = File.read(path)
      {:ok, decoded} = Jason.decode(content)
      assert decoded["topic"] == "AI"
    end
  end

  describe "list_session_files/1" do
    test "lists all files in a session directory" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "list_session")

      # Create some files
      OutputManager.write_research_notes(session_dir, "topic1", "Notes 1")
      OutputManager.write_research_notes(session_dir, "topic2", "Notes 2")
      OutputManager.write_report(session_dir, "final", "Report")

      files = OutputManager.list_session_files(session_dir)
      assert length(files) == 3
    end

    test "returns empty list for empty directory" do
      {:ok, session_dir} = OutputManager.ensure_session_dir(@output_dir, "empty_session")

      files = OutputManager.list_session_files(session_dir)
      assert files == []
    end
  end
end
