defmodule OXCTest do
  use ExUnit.Case, async: true
  doctest OXC

  describe "parse/2" do
    test "parses simple variable declaration" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")
      assert ast.type == :program
      assert [decl] = ast.body
      assert decl.type == :variable_declaration
      assert decl.kind == :const
      assert [declarator] = decl.declarations
      assert declarator.id.name == "x"
      assert declarator.init.value == 1
    end

    test "parses binary expression" do
      {:ok, ast} = OXC.parse("1 + 2", "test.js")
      [stmt] = ast.body
      expr = stmt.expression
      assert expr.type == :binary_expression
      assert expr.operator == "+"
      assert expr.left.value == 1
      assert expr.right.value == 2
    end

    test "parses function declaration" do
      {:ok, ast} = OXC.parse("function add(a, b) { return a + b }", "test.js")
      [func] = ast.body
      assert func.type == :function_declaration
      assert func.id.name == "add"
      assert length(func.params) == 2
    end

    test "parses TypeScript" do
      {:ok, ast} = OXC.parse("const x: number = 42", "test.ts")
      [decl] = ast.body
      assert decl.type == :variable_declaration
      annotation = hd(decl.declarations).id.typeAnnotation
      assert annotation != nil
    end

    test "parses JSX" do
      {:ok, ast} = OXC.parse("<div className='hello'>Hi</div>", "test.jsx")
      [stmt] = ast.body
      assert stmt.expression.type == :jsx_element
    end

    test "parses TSX" do
      {:ok, ast} = OXC.parse("const el: JSX.Element = <App />", "test.tsx")
      assert ast.type == :program
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OXC.parse("const = ;", "bad.js")
      assert is_list(errors)
      assert length(errors) > 0
      assert %{message: msg} = hd(errors)
      assert is_binary(msg)
    end

    test "returns atom keys" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")
      assert Map.has_key?(ast, :type)
      assert Map.has_key?(ast, :body)
    end

    test "parses arrow function" do
      {:ok, ast} = OXC.parse("const f = (x) => x * 2", "test.js")
      [decl] = ast.body
      init = hd(decl.declarations).init
      assert init.type == :arrow_function_expression
    end

    test "parses import/export" do
      {:ok, ast} = OXC.parse("import { foo } from 'bar'; export default 42;", "test.js")
      assert length(ast.body) == 2
      [imp, exp] = ast.body
      assert imp.type == :import_declaration
      assert exp.type == :export_default_declaration
    end

    test "parses async/await" do
      {:ok, ast} = OXC.parse("async function f() { await Promise.resolve(1) }", "test.js")
      [func] = ast.body
      assert func.async == true
    end

    test "type values are snake_case atoms" do
      {:ok, ast} = OXC.parse("import { ref } from 'vue'", "test.js")
      [imp] = ast.body
      assert imp.type == :import_declaration
      assert is_atom(imp.type)
    end

    test "kind values are atoms" do
      {:ok, ast} = OXC.parse("const x = 1; let y = 2;", "test.js")
      [const_decl, let_decl] = ast.body
      assert const_decl.kind == :const
      assert let_decl.kind == :let
    end
  end

  describe "parse!/2" do
    test "returns AST on success" do
      ast = OXC.parse!("const x = 1", "test.js")
      assert ast.type == :program
    end

    test "raises OXC.Error on parse error" do
      assert_raise OXC.Error, ~r/parse error/, fn ->
        OXC.parse!("const = ;", "bad.js")
      end
    end
  end

  describe "valid?/2" do
    test "returns true for valid code" do
      assert OXC.valid?("const x = 1", "test.js")
    end

    test "returns false for invalid code" do
      refute OXC.valid?("const = ;", "bad.js")
    end

    test "validates TypeScript" do
      assert OXC.valid?("const x: number = 42", "test.ts")
    end

    test "validates JSX" do
      assert OXC.valid?("<App />", "test.jsx")
    end
  end

  describe "walk/2" do
    test "visits all nodes with type" do
      {:ok, ast} = OXC.parse("const x = 1; const y = 2;", "test.js")
      names = collect_identifiers(ast)
      assert "x" in names
      assert "y" in names
    end

    test "walks nested structures" do
      {:ok, ast} = OXC.parse("const obj = {a: {b: 1}}", "test.js")

      OXC.walk(ast, fn node ->
        send(self(), {:type, node.type})
      end)

      types = collect_messages(:type)
      assert :program in types
      assert :variable_declaration in types
      assert :object_expression in types
    end

    test "walks a list of nodes" do
      {:ok, ast} = OXC.parse("const x = 1; const y = 2;", "test.js")

      OXC.walk(ast.body, fn
        %{type: :identifier, name: name} -> send(self(), {:name, name})
        _ -> :ok
      end)

      walked = collect_messages(:name)
      assert "x" in walked
      assert "y" in walked
    end
  end

  describe "collect/2" do
    test "collects matching nodes" do
      {:ok, ast} = OXC.parse("import a from 'a'; import b from 'b'; const x = 1;", "test.js")

      imports =
        OXC.collect(ast, fn
          %{type: :import_declaration} = node -> {:keep, node}
          _ -> :skip
        end)

      assert length(imports) == 2
      assert Enum.all?(imports, &(&1.type == :import_declaration))
    end

    test "collects identifiers" do
      {:ok, ast} = OXC.parse("const x = y + z", "test.js")

      names =
        OXC.collect(ast, fn
          %{type: :identifier, name: name} -> {:keep, name}
          _ -> :skip
        end)

      assert "x" in names
      assert "y" in names
      assert "z" in names
    end

    test "returns empty list when nothing matches" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")

      result =
        OXC.collect(ast, fn
          %{type: :import_declaration} = node -> {:keep, node}
          _ -> :skip
        end)

      assert result == []
    end
  end

  describe "transform/3" do
    test "strips TypeScript types" do
      {:ok, js} = OXC.transform("const x: number = 42", "test.ts")
      assert js =~ "const x = 42"
      refute js =~ "number"
    end

    test "strips interface declarations" do
      {:ok, js} = OXC.transform("interface Foo { bar: string }\nconst x = 1", "test.ts")
      assert js =~ "const x = 1"
      refute js =~ "interface"
    end

    test "transforms JSX with automatic runtime" do
      {:ok, js} = OXC.transform("<div>hello</div>", "test.jsx")
      assert js =~ "jsx"
      refute js =~ "<div>"
    end

    test "transforms JSX with classic runtime" do
      {:ok, js} = OXC.transform("<div>hello</div>", "test.jsx", jsx: :classic)
      assert js =~ "createElement"
      refute js =~ "<div>"
    end

    test "transforms JSX with custom pragma" do
      {:ok, js} = OXC.transform("<div>hello</div>", "test.jsx", jsx: :classic, jsx_factory: "h")
      assert js =~ "h("
      refute js =~ "createElement"
    end

    test "transforms JSX with custom pragma and fragment" do
      {:ok, js} =
        OXC.transform("<><span /></>", "test.jsx",
          jsx: :classic,
          jsx_factory: "h",
          jsx_fragment: "Fragment"
        )

      assert js =~ "Fragment"
      refute js =~ "React"
    end

    test "transforms TSX" do
      {:ok, js} = OXC.transform("const el: JSX.Element = <App />", "test.tsx")
      refute js =~ "JSX.Element"
      assert js =~ "jsx" or js =~ "createElement"
    end

    test "preserves plain JS unchanged" do
      {:ok, js} = OXC.transform("const x = 1 + 2", "test.js")
      assert js =~ "const x = 1 + 2"
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OXC.transform("const = ;", "bad.ts")
      assert is_list(errors)
      assert length(errors) > 0
      assert %{message: _} = hd(errors)
    end

    test "handles enum transformation" do
      {:ok, js} = OXC.transform("enum Color { Red, Green, Blue }", "test.ts")
      refute js =~ "enum"
      assert js =~ "Red"
    end

    test "strips type-only imports" do
      {:ok, js} = OXC.transform("import type { Foo } from 'bar'", "test.ts")
      refute js =~ "import"
    end

    test "returns sourcemap when requested" do
      {:ok, result} = OXC.transform("const x: number = 42", "test.ts", sourcemap: true)
      assert is_map(result)
      assert result.code =~ "const x = 42"
      assert is_binary(result.sourcemap)
      assert {:ok, map} = Jason.decode(result.sourcemap)
      assert map["version"] == 3
    end

    test "returns plain string without sourcemap" do
      {:ok, js} = OXC.transform("const x: number = 42", "test.ts")
      assert is_binary(js)
      refute is_map(js)
    end

    test "downlevels with target" do
      {:ok, js} = OXC.transform("const x = a ?? b", "test.js", target: "es2019")
      refute js =~ "??"
    end

    test "transforms JSX with custom import source" do
      {:ok, js} = OXC.transform("<div />", "test.jsx", import_source: "vue")
      assert js =~ "vue/jsx-runtime"
      refute js =~ "react/jsx-runtime"
    end
  end

  describe "transform!/3" do
    test "returns code on success" do
      js = OXC.transform!("const x: number = 42", "test.ts")
      assert js =~ "const x = 42"
    end

    test "raises OXC.Error on error" do
      assert_raise OXC.Error, ~r/transform error/, fn ->
        OXC.transform!("const = ;", "bad.ts")
      end
    end
  end

  describe "minify/3" do
    test "minifies JavaScript" do
      {:ok, min} = OXC.minify("const x = 1 + 2;\nconsole.log(x);", "test.js")
      assert byte_size(min) < byte_size("const x = 1 + 2;\nconsole.log(x);")
      assert min =~ "console.log"
    end

    test "folds constants" do
      {:ok, min} = OXC.minify("const x = 1 + 2; console.log(x);", "test.js")
      assert min =~ "3"
    end

    test "mangles variable names by default" do
      {:ok, min} =
        OXC.minify(
          "function hello() { const longVariableName = 42; return longVariableName; }",
          "test.js"
        )

      refute min =~ "longVariableName"
    end

    test "preserves variable names with mangle: false" do
      {:ok, min} =
        OXC.minify("function hello(longName) { return longName; }", "test.js", mangle: false)

      assert min =~ "longName"
    end

    test "removes dead code" do
      {:ok, min} =
        OXC.minify("if (false) { console.log('dead') } console.log('alive')", "test.js")

      refute min =~ "dead"
      assert min =~ "alive"
    end

    test "removes whitespace and newlines" do
      source = "const   x   =   1;\n\n\nconst   y   =   2;"
      {:ok, min} = OXC.minify(source, "test.js")
      refute min =~ "   "
      refute min =~ "\n\n"
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OXC.minify("const = ;", "bad.js")
      assert is_list(errors)
      assert length(errors) > 0
      assert %{message: _} = hd(errors)
    end

    test "handles empty input" do
      {:ok, min} = OXC.minify("", "test.js")
      assert min == ""
    end
  end

  describe "minify!/3" do
    test "returns code on success" do
      min = OXC.minify!("const x = 1 + 2;", "test.js")
      assert is_binary(min)
    end

    test "raises OXC.Error on error" do
      assert_raise OXC.Error, ~r/minify error/, fn ->
        OXC.minify!("const = ;", "bad.js")
      end
    end
  end

  describe "select/3" do
    test "selects import source maps by selector name" do
      source = """
      import { ref } from 'vue'
      export { foo } from './foo'
      const lazy = import('./lazy')
      """

      assert {:ok, refs} = OXC.select(source, "test.js", :import_sources)

      assert [
               %{specifier: "vue", type: :static, kind: :import},
               %{specifier: "./foo", type: :static, kind: :export},
               %{specifier: "./lazy", type: :dynamic, kind: :import}
             ] = refs
    end

    test "selects import specifier strings by selector name" do
      source = "import { ref } from 'vue'\nconst lazy = import('./lazy')"

      assert OXC.select(source, "test.js", :import_specifiers) == {:ok, ["vue", "./lazy"]}
    end

    test "selects asset URL maps by selector name" do
      source = ~s|const font = new URL("./font.woff2", import.meta.url).href|

      assert {:ok, [%{specifier: "./font.woff2", start: start, end: finish}]} =
               OXC.select(source, "test.js", :asset_urls)

      assert binary_part(source, start, finish - start) == ~s|"./font.woff2"|
    end

    test "asset URLs ignore non import.meta.url bases" do
      source = ~s|const font = new URL("./font.woff2", other.url).href|

      assert OXC.select(source, "test.js", :asset_urls) == {:ok, []}
    end

    test "selects worker URL maps by selector name" do
      source = ~s|new Worker(new URL("./worker.js", import.meta.url), { type: "module" })|

      assert {:ok, [%{specifier: "./worker.js", kind: :worker, start: start, end: finish}]} =
               OXC.select(source, "test.js", :workers)

      assert binary_part(source, start, finish - start) == ~s|"./worker.js"|
    end

    test "selects shared worker URL maps by selector name" do
      source = ~s|new SharedWorker(new URL("./shared.js", import.meta.url))|

      assert {:ok, [%{specifier: "./shared.js", kind: :shared_worker, start: start, end: finish}]} =
               OXC.select(source, "test.js", :workers)

      assert binary_part(source, start, finish - start) == ~s|"./shared.js"|
    end

    test "workers accept generated import.meta.url bases" do
      source = ~s|new Worker(new URL("./worker.js", {}.url), { type: "module" })|

      assert {:ok, [%{specifier: "./worker.js", kind: :worker, start: start, end: finish}]} =
               OXC.select(source, "test.js", :workers)

      assert binary_part(source, start, finish - start) == ~s|"./worker.js"|
    end

    test "workers ignore direct string constructors" do
      source = ~s|new Worker("./worker.js")|

      assert OXC.select(source, "test.js", :workers) == {:ok, []}
    end

    test "selects glob import calls by selector name" do
      source = ~s|const modules = import.meta.glob("./pages/**/*.js")|

      assert {:ok, [%{patterns: ["./pages/**/*.js"], start: start, end: finish}]} =
               OXC.select(source, "test.js", :glob_imports)

      assert binary_part(source, start, finish - start) ==
               ~s|import.meta.glob("./pages/**/*.js")|
    end

    test "selects glob import array patterns by selector name" do
      source = ~s|const modules = import.meta.glob(["./pages/**/*.js", "!./pages/**/test.js"])|

      assert {:ok,
              [%{patterns: ["./pages/**/*.js", "!./pages/**/test.js"], start: start, end: finish}]} =
               OXC.select(source, "test.js", :glob_imports)

      assert binary_part(source, start, finish - start) ==
               ~s|import.meta.glob(["./pages/**/*.js", "!./pages/**/test.js"])|
    end

    test "glob imports ignore dynamic patterns" do
      source = ~s|const modules = import.meta.glob(pattern)|

      assert OXC.select(source, "test.js", :glob_imports) == {:ok, []}
    end

    test "selects import.meta.env references by selector name" do
      source = ~s|if (import.meta.env.DEV) console.log(import.meta.env.MODE)|

      assert {:ok, [%{start: start, end: finish}, %{start: start2, end: finish2}]} =
               OXC.select(source, "test.js", :import_meta_env)

      assert binary_part(source, start, finish - start) == "import.meta.env"
      assert binary_part(source, start2, finish2 - start2) == "import.meta.env"
    end

    test "import.meta.env selector ignores other import.meta properties" do
      source = ~s|console.log(import.meta.url)|

      assert OXC.select(source, "test.js", :import_meta_env) == {:ok, []}
    end

    test "returns errors for invalid syntax" do
      assert {:error, errors} = OXC.select("const = ;", "bad.js", :import_specifiers)
      assert is_list(errors)
      assert %{message: _} = hd(errors)
    end
  end

  describe "rewrite_specifiers/3" do
    test "rewrites matching specifiers" do
      source = "import { ref } from 'vue'\nimport a from './utils'"

      {:ok, result} =
        OXC.rewrite_specifiers(source, "test.js", fn
          "vue" -> {:rewrite, "/@vendor/vue.js"}
          _ -> :keep
        end)

      assert result == "import { ref } from '/@vendor/vue.js'\nimport a from './utils'"
    end

    test "handles export declarations" do
      source = "export { foo } from './foo'\nexport * from './bar'"

      {:ok, result} =
        OXC.rewrite_specifiers(source, "test.js", fn
          "./foo" -> {:rewrite, "./foo.js"}
          "./bar" -> {:rewrite, "./bar.js"}
          _ -> :keep
        end)

      assert result == "export { foo } from './foo.js'\nexport * from './bar.js'"
    end

    test "handles dynamic imports" do
      source = "const m = import('./lazy')"

      {:ok, result} =
        OXC.rewrite_specifiers(source, "test.js", fn
          "./lazy" -> {:rewrite, "./lazy.js"}
          _ -> :keep
        end)

      assert result == "const m = import('./lazy.js')"
    end

    test "keeps all when callback returns :keep" do
      source = "import { ref } from 'vue'"

      {:ok, result} =
        OXC.rewrite_specifiers(source, "test.js", fn _ -> :keep end)

      assert result == source
    end

    test "returns errors for invalid syntax" do
      {:error, errors} =
        OXC.rewrite_specifiers("const = ;", "bad.js", fn _ -> :keep end)

      assert is_list(errors)
    end

    test "rewrites multiple specifiers" do
      source = "import { ref } from 'vue'\nimport { h } from 'preact'"

      {:ok, result} =
        OXC.rewrite_specifiers(source, "test.js", fn
          "vue" -> {:rewrite, "/@vendor/vue.js"}
          "preact" -> {:rewrite, "/@vendor/preact.js"}
          _ -> :keep
        end)

      assert result =~ "/@vendor/vue.js"
      assert result =~ "/@vendor/preact.js"
    end
  end

  defp collect_identifiers(ast) do
    OXC.collect(ast, fn
      %{type: :identifier, name: name} -> {:keep, name}
      _ -> :skip
    end)
  end

  describe "postwalk/2" do
    test "visits all nodes" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")
      types = :ets.new(:types, [:bag, :private])

      OXC.postwalk(ast, fn node ->
        :ets.insert(types, {node.type})
        node
      end)

      result = :ets.tab2list(types) |> Enum.map(&elem(&1, 0))
      :ets.delete(types)

      assert :program in result
      assert :variable_declaration in result
      assert :identifier in result
    end

    test "returns modified tree" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")

      result =
        OXC.postwalk(ast, fn
          %{type: :identifier, name: "x"} = node -> %{node | name: "y"}
          node -> node
        end)

      [decl] = result.body
      [declarator] = decl.declarations
      assert declarator.id.name == "y"
    end

    test "handles list of nodes" do
      {:ok, ast} = OXC.parse("const x = 1; const y = 2;", "test.js")

      result =
        OXC.postwalk(ast.body, fn
          %{type: :identifier, name: "x"} = node -> %{node | name: "a"}
          node -> node
        end)

      assert is_list(result)
      assert length(result) == 2
    end
  end

  describe "postwalk/3" do
    test "collects data with accumulator" do
      {:ok, ast} = OXC.parse("const x = y + z", "test.js")

      {_ast, names} =
        OXC.postwalk(ast, [], fn
          %{type: :identifier, name: name} = node, acc -> {node, [name | acc]}
          node, acc -> {node, acc}
        end)

      assert Enum.sort(names) == ["x", "y", "z"]
    end

    test "collects patches for import rewriting" do
      source = "import { ref } from 'vue'\nimport a from './utils'"
      {:ok, ast} = OXC.parse(source, "test.ts")

      {_ast, patches} =
        OXC.postwalk(ast, [], fn
          %{type: :import_declaration, source: %{value: "vue"} = src} = node, patches ->
            {node, [%{start: src.start, end: src.end, change: "'/@vendor/vue.js'"} | patches]}

          node, patches ->
            {node, patches}
        end)

      assert OXC.patch_string(source, patches) ==
               "import { ref } from '/@vendor/vue.js'\nimport a from './utils'"
    end

    test "handles list of nodes with accumulator" do
      {:ok, ast} = OXC.parse("const x = 1; const y = 2;", "test.js")

      {result, names} =
        OXC.postwalk(ast.body, [], fn
          %{type: :identifier, name: name} = node, acc -> {node, [name | acc]}
          node, acc -> {node, acc}
        end)

      assert is_list(result)
      assert "x" in names
      assert "y" in names
    end
  end

  describe "patch_string/2" do
    test "replaces a single range" do
      assert OXC.patch_string("hello world", [%{start: 6, end: 11, change: "elixir"}]) ==
               "hello elixir"
    end

    test "applies multiple non-overlapping patches" do
      source = "aaa bbb ccc"

      patches = [
        %{start: 0, end: 3, change: "xxx"},
        %{start: 8, end: 11, change: "zzz"}
      ]

      assert OXC.patch_string(source, patches) == "xxx bbb zzz"
    end

    test "deduplicates patches with same range" do
      source = "hello world"

      patches = [
        %{start: 6, end: 11, change: "elixir"},
        %{start: 6, end: 11, change: "elixir"}
      ]

      assert OXC.patch_string(source, patches) == "hello elixir"
    end

    test "handles empty patches" do
      assert OXC.patch_string("hello", []) == "hello"
    end

    test "handles insertion (start == end)" do
      assert OXC.patch_string("hello world", [%{start: 5, end: 5, change: ","}]) ==
               "hello, world"
    end
  end

  describe "transform_many/2" do
    test "transforms multiple files in parallel" do
      results =
        OXC.transform_many([
          {"const x: number = 1", "a.ts"},
          {"const y: number = 2", "b.ts"}
        ])

      assert [{:ok, code_a}, {:ok, code_b}] = results
      assert code_a =~ "const x = 1"
      assert code_b =~ "const y = 2"
    end

    test "handles JSX with shared options" do
      results =
        OXC.transform_many(
          [{"const A = () => <div />", "a.tsx"}, {"const B = () => <span />", "b.tsx"}],
          jsx: :classic
        )

      assert [{:ok, code_a}, {:ok, code_b}] = results
      assert code_a =~ "createElement"
      assert code_b =~ "createElement"
    end

    test "returns per-file errors without failing the batch" do
      results =
        OXC.transform_many([
          {"const x = 1", "good.ts"},
          {"const = ;", "bad.ts"},
          {"const y = 2", "also_good.ts"}
        ])

      assert [{:ok, _}, {:error, errors}, {:ok, _}] = results
      assert is_list(errors)
    end

    test "returns empty list for empty input" do
      assert [] = OXC.transform_many([])
    end
  end

  describe "parse/2 recursion depth" do
    test "handles deeply nested expressions without recursion limit" do
      depth = 200

      code =
        "const x = " <>
          String.duplicate("(", depth) <> "42" <> String.duplicate(")", depth) <> ";"

      assert {:ok, %{type: :program}} = OXC.parse(code, "deep.js")
    end
  end

  describe "iodata inputs" do
    test "source APIs accept iodata" do
      source = ["const ", [?x], " = ", [?1], ";"]

      assert {:ok, %{type: :program}} = OXC.parse(source, "test.js")
      assert OXC.valid?(source, "test.js")
      assert {:ok, js} = OXC.transform(["const x", ": number = 1"], "test.ts")
      assert js == "const x = 1;\n"
      assert {:ok, min} = OXC.minify(["const x = ", "1 + 2;"], "test.js")
      assert min =~ "const"

      assert {:ok, [%{specifier: "vue"}]} =
               OXC.select(["import { ref } ", "from 'vue'"], "test.js", :import_sources)
    end

    test "batch and patch APIs accept iodata" do
      assert [{:ok, "const x = 1;\n"}] =
               OXC.transform_many([{["const x", ": number = 1"], "test.ts"}])

      assert {:ok, "import { ref } from '/@vendor/vue.js'"} =
               OXC.rewrite_specifiers(["import { ref } ", "from 'vue'"], "test.js", fn "vue" ->
                 {:rewrite, ["/@vendor/", "vue", ".js"]}
               end)

      assert OXC.patch_string(["hello", " world"], [%{start: 6, end: 11, change: ["el", "ixir"]}]) ==
               "hello elixir"
    end
  end

  defp collect_messages(tag) do
    collect_messages(tag, [])
  end

  defp collect_messages(tag, acc) do
    receive do
      {^tag, value} -> collect_messages(tag, [value | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
