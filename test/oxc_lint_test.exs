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

    test "accepts iodata source" do
      {:ok, diags} = OXC.Lint.run(["debug", "ger;"], "test.js", rules: %{"no-debugger" => :deny})
      assert Enum.any?(diags, &(&1.rule =~ "no-debugger"))
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

  describe "run/2 with type-aware rules" do
    test "requires a tsgolint executable" do
      assert {:error, [message]} =
               OXC.Lint.run(["test.ts"],
                 type_aware: true,
                 tsgolint: "/definitely/missing/tsgolint"
               )

      assert message =~ "tsgolint executable not found"
    end

    test "parses tsgolint diagnostic frames" do
      diagnostic = %{
        "kind" => 1,
        "range" => %{"pos" => 4, "end" => 12},
        "rule" => "no-floating-promises",
        "message" => %{"id" => "floating", "description" => "Promise is not handled"},
        "file_path" => "/tmp/app.ts",
        "labeled_ranges" => [%{"label" => "promise", "range" => %{"pos" => 4, "end" => 12}}]
      }

      frame = frame(1, Jason.encode!(diagnostic))

      assert {:ok, [diag]} =
               OXC.Lint.TypeAware.parse_output(frame, %{"no-floating-promises" => :deny})

      assert %OXC.Lint.TypeAware.Diagnostic{} = diag
      assert diag.rule == "typescript/no-floating-promises"
      assert diag.message == "Promise is not handled"
      assert diag.severity == :deny
      assert diag.file == "/tmp/app.ts"
      assert diag.span == {4, 12}
      assert diag.labels == [{4, 12}]
    end

    test "runs tsgolint headless with encoded payload and normalizes diagnostics" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "oxc-type-aware-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      executable = fake_tsgolint(tmp_dir)
      file = Path.join(tmp_dir, "app.ts")
      File.write!(file, "async function save() {}\nsave()\n")

      assert {:ok, [%OXC.Lint.TypeAware.Diagnostic{} = diag]} =
               OXC.Lint.run([file],
                 type_aware: true,
                 tsgolint: executable,
                 type_check: true,
                 fix: true,
                 fix_suggestions: true,
                 source_overrides: %{file => "save()"},
                 rules: %{
                   "typescript/no-floating-promises" => {:deny, %{ignoreVoid: true}}
                 }
               )

      assert diag.rule == "typescript/no-floating-promises"
      assert diag.severity == :deny
      assert diag.file == file
      assert diag.span == {1, 5}

      payload = tmp_dir |> Path.join("payload.json") |> File.read!() |> Jason.decode!()
      argv = tmp_dir |> Path.join("argv.json") |> File.read!() |> Jason.decode!()

      assert argv == ["headless", "-fix-suggestions", "-fix"]
      assert payload["version"] == 2
      assert payload["report_syntactic"] == true
      assert payload["report_semantic"] == true
      assert payload["source_overrides"] == %{file => "save()"}
      assert [%{"file_paths" => [^file], "rules" => [rule]}] = payload["configs"]
      assert rule == %{"name" => "no-floating-promises", "options" => %{"ignoreVoid" => true}}
    end

    test "parses multiple diagnostic frames and ignores timing frames" do
      first = frame(1, Jason.encode!(diagnostic_payload("no-floating-promises", 1, 2)))
      timing = frame(2, Jason.encode!(%{"rules" => []}))
      second = frame(1, Jason.encode!(diagnostic_payload("no-misused-promises", 3, 4)))

      assert {:ok, [first_diag, second_diag]} =
               OXC.Lint.TypeAware.parse_output(first <> timing <> second, %{
                 "no-floating-promises" => :deny,
                 "no-misused-promises" => :warn
               })

      assert first_diag.rule == "typescript/no-floating-promises"
      assert first_diag.severity == :deny
      assert second_diag.rule == "typescript/no-misused-promises"
      assert second_diag.severity == :warn
    end

    test "returns diagnostics from a nonzero tsgolint exit" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "oxc-type-aware-exit-diag-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      executable = fake_tsgolint(tmp_dir, exit_status: 1)
      file = Path.join(tmp_dir, "app.ts")
      File.write!(file, "Promise.resolve()")

      assert {:ok, [diag]} =
               OXC.Lint.run([file],
                 type_aware: true,
                 tsgolint: executable,
                 rules: %{"typescript/no-floating-promises" => :deny}
               )

      assert diag.rule == "typescript/no-floating-promises"
      assert diag.severity == :deny
    end

    test "returns errors from a nonzero tsgolint error-only exit" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "oxc-type-aware-exit-error-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      executable = fake_tsgolint_error(tmp_dir, "tsgolint exploded")

      assert {:error, ["tsgolint exploded"]} =
               OXC.Lint.run([Path.join(tmp_dir, "app.ts")],
                 type_aware: true,
                 tsgolint: executable,
                 rules: %{"typescript/no-floating-promises" => :deny}
               )
    end

    test "parses tsgolint error frames" do
      frame = frame(0, Jason.encode!(%{"error" => "boom"}))
      assert {:error, ["boom"]} = OXC.Lint.TypeAware.parse_output(frame)
    end

    test "ignores truncated trailing frames after valid diagnostics" do
      valid = frame(1, Jason.encode!(diagnostic_payload("no-floating-promises", 1, 2)))

      assert {:ok, [_diag]} =
               OXC.Lint.TypeAware.parse_output(valid <> <<10::little-32, 1, "bad">>)
    end

    test "real tsgolint reports source override diagnostics when available" do
      with {:ok, executable} <- real_tsgolint() do
        tmp_dir =
          Path.join(
            System.tmp_dir!(),
            "oxc-type-aware-real-override-#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(tmp_dir)
        on_exit(fn -> File.rm_rf!(tmp_dir) end)

        write_tsconfig!(tmp_dir)
        file = Path.join(tmp_dir, "app.ts")
        File.write!(file, "const ok = 1\n")

        override = "async function save() { return 1 }\nsave()\n"

        assert {:ok, diagnostics} =
                 OXC.Lint.run([file],
                   type_aware: true,
                   tsgolint: executable,
                   source_overrides: %{file => override},
                   rules: %{"typescript/no-floating-promises" => :deny}
                 )

        assert Enum.any?(diagnostics, &(&1.rule == "typescript/no-floating-promises"))
      end
    end

    test "real tsgolint reports type-check diagnostics when available" do
      with {:ok, executable} <- real_tsgolint() do
        tmp_dir =
          Path.join(
            System.tmp_dir!(),
            "oxc-type-aware-real-typecheck-#{System.unique_integer([:positive])}"
          )

        File.mkdir_p!(tmp_dir)
        on_exit(fn -> File.rm_rf!(tmp_dir) end)

        write_tsconfig!(tmp_dir)
        file = Path.join(tmp_dir, "app.ts")
        File.write!(file, "const value: string = 1\n")

        assert {:ok, diagnostics} =
                 OXC.Lint.run([file],
                   type_aware: true,
                   tsgolint: executable,
                   type_check: true,
                   rules: %{}
                 )

        assert Enum.any?(diagnostics, &String.starts_with?(&1.rule, "typescript/TS"))
      end
    end

    defp diagnostic_payload(rule, start, stop) do
      %{
        "kind" => 1,
        "range" => %{"pos" => start, "end" => stop},
        "rule" => rule,
        "message" => %{"id" => rule, "description" => "diagnostic from #{rule}"},
        "file_path" => "/tmp/app.ts",
        "labeled_ranges" => [%{"label" => "label", "range" => %{"pos" => start, "end" => stop}}]
      }
    end

    defp fake_tsgolint(tmp_dir, opts \\ []) do
      executable = Path.join(tmp_dir, "tsgolint")
      payload_path = Path.join(tmp_dir, "payload.json")
      argv_path = Path.join(tmp_dir, "argv.json")
      exit_status = Keyword.get(opts, :exit_status, 0)

      File.write!(executable, """
      #!/usr/bin/env python3
      import json, struct, sys
      payload = sys.stdin.read()
      open(#{inspect(payload_path)}, "w").write(payload)
      open(#{inspect(argv_path)}, "w").write(json.dumps(sys.argv[1:]))
      data = json.loads(payload)
      file_path = data["configs"][0]["file_paths"][0]
      body = json.dumps({
        "kind": 1,
        "range": {"pos": 1, "end": 5},
        "rule": "no-floating-promises",
        "message": {"id": "no-floating-promises", "description": "Promise is not handled"},
        "file_path": file_path,
        "labeled_ranges": [{"label": "promise", "range": {"pos": 1, "end": 5}}]
      }).encode()
      sys.stdout.buffer.write(struct.pack("<IB", len(body), 1) + body)
      sys.exit(#{exit_status})
      """)

      File.chmod!(executable, 0o755)
      executable
    end

    defp fake_tsgolint_error(tmp_dir, message) do
      executable = Path.join(tmp_dir, "tsgolint-error")

      File.write!(executable, """
      #!/usr/bin/env python3
      import json, struct, sys
      sys.stdin.read()
      body = json.dumps({"error": #{inspect(message)}}).encode()
      sys.stdout.buffer.write(struct.pack("<IB", len(body), 0) + body)
      sys.exit(1)
      """)

      File.chmod!(executable, 0o755)
      executable
    end

    defp real_tsgolint do
      case System.find_executable("tsgolint") do
        nil -> :unavailable
        executable -> {:ok, executable}
      end
    end

    defp write_tsconfig!(dir) do
      File.write!(
        Path.join(dir, "tsconfig.json"),
        Jason.encode!(%{
          "compilerOptions" => %{
            "target" => "ES2022",
            "module" => "ESNext",
            "moduleResolution" => "Bundler",
            "strict" => true,
            "lib" => ["ES2022"]
          },
          "include" => ["*.ts"]
        })
      )
    end

    defp frame(type, payload) do
      <<byte_size(payload)::little-32, type::unsigned-8, payload::binary>>
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
