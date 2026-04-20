defmodule OXC.LintTest do
  use ExUnit.Case, async: true

  describe "run/3 with built-in rules" do
    test "detects eqeqeq violation with configured severity" do
      {:ok, diags} = OXC.Lint.run("x == y", "test.js", rules: %{"eqeqeq" => :deny})
      diag = Enum.find(diags, &(&1.rule =~ "eqeqeq"))
      assert diag
      assert diag.severity == :deny
    end

    test "detects no-debugger" do
      {:ok, diags} = OXC.Lint.run("debugger;", "test.js", rules: %{"no-debugger" => :deny})
      diag = Enum.find(diags, &(&1.rule =~ "no-debugger"))
      assert diag
      assert diag.severity == :deny
    end

    test "returns empty list for clean code" do
      {:ok, diags} = OXC.Lint.run("export const x = 1;\n", "test.ts")
      assert diags == []
    end

    test "diagnostic has expected shape" do
      {:ok, [diag | _]} = OXC.Lint.run("x == y", "test.js", rules: %{"eqeqeq" => :warn})
      assert is_binary(diag.rule)
      assert is_binary(diag.message)
      assert diag.severity in [:warn, :deny, :allow]
      {start, stop} = diag.span
      assert is_integer(start) and is_integer(stop)
      assert is_list(diag.labels)
    end

    test "span points to correct location" do
      source = "const a = 1;\nx == y;\n"
      {:ok, diags} = OXC.Lint.run(source, "test.js", rules: %{"eqeqeq" => :warn})
      diag = Enum.find(diags, &(&1.rule =~ "eqeqeq"))
      assert diag
      {start, _stop} = diag.span
      assert start >= 13
    end

    test "returns parse errors for invalid syntax" do
      {:error, errors} = OXC.Lint.run("const = ;", "bad.js")
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "warn severity is default for correctness rules" do
      {:ok, diags} = OXC.Lint.run("x == y", "test.js", rules: %{"eqeqeq" => :warn})
      diag = Enum.find(diags, &(&1.rule =~ "eqeqeq"))
      assert diag.severity == :warn
    end
  end

  describe "run/3 with plugins" do
    test "typescript plugin catches no-explicit-any" do
      source = "function foo(x: any) { return x; }"

      {:ok, diags} =
        OXC.Lint.run(source, "test.ts",
          plugins: [:typescript],
          rules: %{"typescript/no-explicit-any" => :warn}
        )

      assert Enum.any?(diags, &(&1.rule =~ "no-explicit-any"))
    end

    test "react plugin catches no-direct-mutation-state" do
      source = """
      import React from 'react';
      class Foo extends React.Component {
        onClick() { this.state.name = 'bar'; }
      }
      """

      {:ok, diags} =
        OXC.Lint.run(source, "test.jsx",
          plugins: [:react],
          rules: %{"react/no-direct-mutation-state" => :deny}
        )

      assert Enum.any?(diags, &(&1.rule =~ "no-direct-mutation-state"))
    end
  end

  describe "run/3 with custom Elixir rules" do
    defmodule NoConsoleLog do
      @behaviour OXC.Lint.Rule

      @impl true
      def meta do
        %{
          name: "custom/no-console-log",
          description: "Disallow console.log",
          category: :restriction,
          fixable: false
        }
      end

      @impl true
      def run(ast, _context) do
        OXC.collect(ast, fn
          %{
            type: :call_expression,
            callee: %{
              type: :member_expression,
              object: %{type: :identifier, name: "console"},
              property: %{type: :identifier, name: "log"}
            },
            start: start,
            end: stop
          } ->
            {:keep, %{span: {start, stop}, message: "Unexpected console.log"}}

          _ ->
            :skip
        end)
      end
    end

    defmodule NoBannedImports do
      @behaviour OXC.Lint.Rule

      @banned ~w(lodash moment)

      @impl true
      def meta do
        %{
          name: "custom/no-banned-imports",
          description: "Disallow banned packages",
          category: :restriction,
          fixable: false
        }
      end

      @impl true
      def run(ast, _context) do
        OXC.collect(ast, fn
          %{type: :import_declaration, source: %{value: specifier, start: s, end: e}} ->
            if specifier in @banned do
              {:keep, %{span: {s, e}, message: "Import '#{specifier}' is banned"}}
            else
              :skip
            end

          _ ->
            :skip
        end)
      end
    end

    test "custom rule detects console.log" do
      {:ok, diags} =
        OXC.Lint.run("console.log('hi')", "test.js", custom_rules: [{NoConsoleLog, :warn}])

      assert Enum.any?(diags, &(&1.rule == "custom/no-console-log"))
      assert Enum.any?(diags, &(&1.message == "Unexpected console.log"))
    end

    test "custom rule detects banned imports" do
      source = """
      import _ from 'lodash';
      import dayjs from 'dayjs';
      """

      {:ok, diags} =
        OXC.Lint.run(source, "test.js", custom_rules: [{NoBannedImports, :deny}])

      banned = Enum.filter(diags, &(&1.rule == "custom/no-banned-imports"))
      assert length(banned) == 1
      assert hd(banned).message =~ "lodash"
      assert hd(banned).severity == :deny
    end

    test "custom rule receives settings" do
      defmodule SettingsRule do
        @behaviour OXC.Lint.Rule

        @impl true
        def meta, do: %{name: "test/settings", description: "", category: :style, fixable: false}

        @impl true
        def run(_ast, context) do
          if context.settings[:flag] do
            [%{span: {0, 0}, message: "flag is set"}]
          else
            []
          end
        end
      end

      {:ok, diags} =
        OXC.Lint.run("const x = 1", "test.js",
          custom_rules: [{SettingsRule, :warn}],
          settings: %{flag: true}
        )

      assert Enum.any?(diags, &(&1.message == "flag is set"))

      {:ok, diags} =
        OXC.Lint.run("const x = 1", "test.js",
          custom_rules: [{SettingsRule, :warn}],
          settings: %{flag: false}
        )

      refute Enum.any?(diags, &(&1.message == "flag is set"))
    end

    test "built-in and custom rules run together" do
      source = "x == y; console.log('hi');"

      {:ok, diags} =
        OXC.Lint.run(source, "test.js",
          rules: %{"eqeqeq" => :warn},
          custom_rules: [{NoConsoleLog, :warn}]
        )

      assert Enum.any?(diags, &(&1.rule =~ "eqeqeq"))
      assert Enum.any?(diags, &(&1.rule == "custom/no-console-log"))
    end
  end
end
