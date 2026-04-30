defmodule ClaudeAgentSDK.PromotionPathExampleBoundaryTest do
  use ExUnit.Case, async: true

  test "SDK-direct promotion examples do not reference ASM" do
    examples = Path.wildcard("examples/promotion_path/sdk_direct_*.exs")
    assert examples != []

    for path <- examples do
      assert asm_references(path) == []
    end
  end

  defp asm_references(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!()
    |> collect_asm_references()
  end

  defp collect_asm_references(ast) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, aliases} = node, refs ->
          refs =
            if asm_alias?(aliases), do: [{meta[:line], Module.concat(aliases)} | refs], else: refs

          {node, refs}

        {:apply, meta, [{:__aliases__, _, aliases}, _function, _args]} = node, refs ->
          refs = if asm_alias?(aliases), do: [{meta[:line], :dynamic_apply} | refs], else: refs
          {node, refs}

        node, refs ->
          {node, refs}
      end)

    Enum.reverse(refs)
  end

  defp asm_alias?([:ASM | _rest]), do: true
  defp asm_alias?([:"Elixir", :ASM | _rest]), do: true
  defp asm_alias?(_aliases), do: false
end
