defmodule ResearchAgent.OutputManager do
  @moduledoc """
  Manages output file organization for research sessions.

  The OutputManager handles:
  - Session directory creation
  - Research notes writing
  - Final report generation
  - Structured data export (JSON)

  ## Directory Structure

  ```
  output_dir/
    sessions/
      session_abc123/
        notes_topic_name.md
        report_topic_name.md
        data_analysis.json
        transcript.json
  ```

  ## Example

      {:ok, dir} = OutputManager.ensure_session_dir("./output", "session_123")
      {:ok, path} = OutputManager.write_research_notes(dir, "AI Safety", notes_content)
      {:ok, path} = OutputManager.write_report(dir, "AI Safety", report_content)
  """

  require Logger

  @doc """
  Ensures a session directory exists.

  Creates the directory structure if it doesn't exist.

  ## Returns

  `{:ok, path}` where path is the full session directory path.
  """
  @spec ensure_session_dir(String.t(), String.t()) :: {:ok, String.t()}
  def ensure_session_dir(output_dir, session_id) do
    session_dir = Path.join([output_dir, "sessions", session_id])
    File.mkdir_p!(session_dir)
    {:ok, session_dir}
  end

  @doc """
  Writes research notes to a markdown file.

  ## Parameters

  - `session_dir` - The session directory path
  - `topic` - The research topic (used in filename)
  - `notes` - The markdown content

  ## Returns

  `{:ok, path}` - Path to the created file
  """
  @spec write_research_notes(String.t(), String.t(), String.t()) :: {:ok, String.t()}
  def write_research_notes(session_dir, topic, notes) do
    filename = "notes_#{sanitize_filename(topic)}.md"
    path = Path.join(session_dir, filename)

    File.write!(path, notes)
    Logger.info("[OutputManager] Wrote research notes to #{path}")

    {:ok, path}
  end

  @doc """
  Writes a final report to a markdown file.

  ## Parameters

  - `session_dir` - The session directory path
  - `topic` - The research topic (used in filename)
  - `report` - The markdown content

  ## Returns

  `{:ok, path}` - Path to the created file
  """
  @spec write_report(String.t(), String.t(), String.t()) :: {:ok, String.t()}
  def write_report(session_dir, topic, report) do
    filename = "report_#{sanitize_filename(topic)}.md"
    path = Path.join(session_dir, filename)

    File.write!(path, report)
    Logger.info("[OutputManager] Wrote report to #{path}")

    {:ok, path}
  end

  @doc """
  Writes structured data to a JSON file.

  ## Parameters

  - `session_dir` - The session directory path
  - `name` - Name for the data file
  - `data` - Map or list to serialize

  ## Returns

  `{:ok, path}` - Path to the created file
  """
  @spec write_structured_data(String.t(), String.t(), map() | list()) :: {:ok, String.t()}
  def write_structured_data(session_dir, name, data) do
    filename = "#{sanitize_filename(name)}.json"
    path = Path.join(session_dir, filename)

    json = Jason.encode!(data, pretty: true)
    File.write!(path, json)

    Logger.info("[OutputManager] Wrote structured data to #{path}")

    {:ok, path}
  end

  @doc """
  Lists all files in a session directory.

  ## Returns

  List of file paths.
  """
  @spec list_session_files(String.t()) :: [String.t()]
  def list_session_files(session_dir) do
    case File.ls(session_dir) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(session_dir, &1))
        |> Enum.filter(&File.regular?/1)

      {:error, _} ->
        []
    end
  end

  # Private Functions

  @spec sanitize_filename(String.t()) :: String.t()
  defp sanitize_filename(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.slice(0, 50)
  end
end
