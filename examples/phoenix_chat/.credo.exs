%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Design.AliasUsage, false},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Refactor.MapInto, false},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.LazyLogging, false}
        ]
      }
    }
  ]
}
