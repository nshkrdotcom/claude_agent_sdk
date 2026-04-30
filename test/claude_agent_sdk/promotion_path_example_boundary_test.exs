defmodule ClaudeAgentSDK.PromotionPathExampleBoundaryTest do
  use ExUnit.Case, async: true

  test "SDK-direct promotion examples do not reference ASM" do
    examples = Path.wildcard("examples/promotion_path/sdk_direct_*.exs")
    assert examples != []

    for path <- examples do
      assert forbidden_references(path, [ASM]) == []
    end
  end

  test "AST boundary helper catches direct and dynamic ASM references" do
    source = """
    defmodule BadSdkDirectExample do
      import ASM
      require ASM
      def remote, do: ASM.query(:claude, "prompt", [])
      def dynamic, do: apply(ASM, :query, [:claude, "prompt", []])
    end
    """

    refs = source_references(source, [ASM])

    assert Enum.any?(refs, &match?(%{kind: :import, module: ASM}, &1))
    assert Enum.any?(refs, &match?(%{kind: :require, module: ASM}, &1))
    assert Enum.any?(refs, &match?(%{kind: :remote_call, module: ASM}, &1))
    assert Enum.any?(refs, &match?(%{kind: :apply, module: ASM}, &1))
  end

  defp forbidden_references(path, forbidden_modules) do
    path
    |> File.read!()
    |> source_references(forbidden_modules)
  end

  defp source_references(source, forbidden_modules) do
    forbidden_parts = Enum.map(forbidden_modules, &Module.split/1)

    source
    |> Code.string_to_quoted!()
    |> collect_forbidden_references(forbidden_parts)
  end

  defp collect_forbidden_references(ast, forbidden_parts) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {op, meta, [{:__aliases__, _, aliases} | _rest]} = node, refs
        when op in [:alias, :import, :require] ->
          {node, references(op, aliases, meta, forbidden_parts) ++ refs}

        {{:., meta, [{:__aliases__, _, aliases}, function]}, _, _args} = node, refs ->
          {node, references(:remote_call, aliases, meta, forbidden_parts, function) ++ refs}

        {:apply, meta, [{:__aliases__, _, aliases}, _function, _args]} = node, refs ->
          {node, references(:apply, aliases, meta, forbidden_parts) ++ refs}

        {:__aliases__, meta, aliases} = node, refs ->
          {node, references(:module_reference, aliases, meta, forbidden_parts) ++ refs}

        node, refs ->
          {node, refs}
      end)

    Enum.reverse(refs)
  end

  defp references(kind, aliases, meta, forbidden_parts, function \\ nil) do
    parts = alias_parts(aliases)
    forbidden = Enum.find(forbidden_parts, &(Enum.take(parts, length(&1)) == &1))

    if forbidden do
      [%{kind: kind, module: Module.concat(forbidden), function: function, line: meta[:line]}]
    else
      []
    end
  end

  defp alias_parts([:"Elixir" | rest]), do: Enum.map(rest, &to_string/1)
  defp alias_parts(parts), do: Enum.map(parts, &to_string/1)
end
