defmodule ClaudeAgentSDK.Schema do
  @moduledoc false

  alias CliSubprocessCore.Schema, as: CoreSchema

  defdelegate parse(schema, value, tag), to: CoreSchema
  defdelegate parse!(schema, value, tag), to: CoreSchema
  defdelegate split_extra(map, keys), to: CoreSchema
end
