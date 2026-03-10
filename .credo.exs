%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        enabled: [
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []}
        ]
      }
    }
  ]
}
