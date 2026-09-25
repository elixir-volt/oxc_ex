defmodule OXC.DiagnosticTest do
  use ExUnit.Case, async: true

  describe "from_raw/3" do
    test "locates the primary label and keeps secondary labels" do
      source = "const a = 1;\nconst a = 2;\n"

      [diagnostic] =
        OXC.Diagnostic.from_raw(
          [
            %{
              message: "Identifier `a` has already been declared",
              help: "Rename one of them",
              labels: [{19, 20, "redeclared here"}, {6, 7, "first declared here"}]
            }
          ],
          "app.js",
          source
        )

      assert diagnostic == %{
               source: nil,
               file: "app.js",
               severity: :error,
               message: "Identifier `a` has already been declared",
               position: {2, 7},
               span: {2, 8},
               stacktrace: [],
               details: "Rename one of them",
               labels: [%{position: {1, 7}, span: {1, 8}, message: "first declared here"}]
             }
    end

    test "counts columns in characters, not bytes" do
      [diagnostic] =
        OXC.Diagnostic.from_raw(
          [%{message: "x", labels: [{15, 16, nil}]}],
          "a.js",
          "'ёж' + 'ё'; x"
        )

      # `x` starts at byte 15 but is the 13th character.
      assert diagnostic.position == {1, 13}
    end

    test "clamps offsets past the end of the source" do
      [diagnostic] =
        OXC.Diagnostic.from_raw([%{message: "x", labels: [{2, 99, nil}]}], "a.js", "ab\ncd")

      assert diagnostic.span == {2, 3}
    end

    test "uses Elixir's unknown position without a source or labels" do
      assert [%{position: 0, span: nil, file: nil, message: "boom"}] =
               OXC.Diagnostic.from_raw(["boom"], nil, nil)

      assert [%{position: 0, span: nil, file: "a.js"}] =
               OXC.Diagnostic.from_raw([%{message: "no labels", labels: []}], "a.js", "x")
    end

    test "turns fixes into patches" do
      [diagnostic] =
        OXC.Diagnostic.from_raw(
          [%{message: "x", labels: [{0, 9, nil}], fixes: [{0, 9, ""}]}],
          "a.js",
          "debugger;"
        )

      assert diagnostic.fixes == [%{start: 0, end: 9, change: ""}]
    end
  end

  describe "format/1" do
    test "formats like Elixir compiler output" do
      assert OXC.Diagnostic.format(%{file: "a.js", position: {2, 7}, message: "Unexpected token"}) ==
               "a.js:2:7: Unexpected token"

      assert OXC.Diagnostic.format(%{file: "a.js", position: 0, message: "Unexpected token"}) ==
               "a.js: Unexpected token"

      assert OXC.Diagnostic.format(%{file: nil, position: 0, message: "boom"}) == "boom"
    end
  end
end
