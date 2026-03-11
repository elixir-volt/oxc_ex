defmodule OxcExTest do
  use ExUnit.Case, async: true

  describe "parse/2" do
    test "parses simple variable declaration" do
      {:ok, ast} = OxcEx.parse("const x = 1", "test.js")
      assert ast.type == "Program"
      assert [decl] = ast.body
      assert decl.type == "VariableDeclaration"
      assert decl.kind == "const"
      assert [declarator] = decl.declarations
      assert declarator.id.name == "x"
      assert declarator.init.value == 1
    end

    test "parses binary expression" do
      {:ok, ast} = OxcEx.parse("1 + 2", "test.js")
      [stmt] = ast.body
      expr = stmt.expression
      assert expr.type == "BinaryExpression"
      assert expr.operator == "+"
      assert expr.left.value == 1
      assert expr.right.value == 2
    end

    test "parses function declaration" do
      {:ok, ast} = OxcEx.parse("function add(a, b) { return a + b }", "test.js")
      [func] = ast.body
      assert func.type == "FunctionDeclaration"
      assert func.id.name == "add"
      assert length(func.params) == 2
    end

    test "parses TypeScript" do
      {:ok, ast} = OxcEx.parse("const x: number = 42", "test.ts")
      [decl] = ast.body
      assert decl.type == "VariableDeclaration"
      annotation = hd(decl.declarations).id.typeAnnotation
      assert annotation != nil
    end

    test "parses JSX" do
      {:ok, ast} = OxcEx.parse("<div className='hello'>Hi</div>", "test.jsx")
      [stmt] = ast.body
      assert stmt.expression.type == "JSXElement"
    end

    test "parses TSX" do
      {:ok, ast} = OxcEx.parse("const el: JSX.Element = <App />", "test.tsx")
      assert ast.type == "Program"
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OxcEx.parse("const = ;", "bad.js")
      assert is_list(errors)
      assert length(errors) > 0
      assert %{message: msg} = hd(errors)
      assert is_binary(msg)
    end

    test "returns atom keys" do
      {:ok, ast} = OxcEx.parse("const x = 1", "test.js")
      assert Map.has_key?(ast, :type)
      assert Map.has_key?(ast, :body)
    end

    test "parses arrow function" do
      {:ok, ast} = OxcEx.parse("const f = (x) => x * 2", "test.js")
      [decl] = ast.body
      init = hd(decl.declarations).init
      assert init.type == "ArrowFunctionExpression"
    end

    test "parses import/export" do
      {:ok, ast} = OxcEx.parse("import { foo } from 'bar'; export default 42;", "test.js")
      assert length(ast.body) == 2
      [imp, exp] = ast.body
      assert imp.type == "ImportDeclaration"
      assert exp.type == "ExportDefaultDeclaration"
    end

    test "parses async/await" do
      {:ok, ast} = OxcEx.parse("async function f() { await Promise.resolve(1) }", "test.js")
      [func] = ast.body
      assert func.async == true
    end
  end

  describe "parse!/2" do
    test "returns AST on success" do
      ast = OxcEx.parse!("const x = 1", "test.js")
      assert ast.type == "Program"
    end

    test "raises on parse error" do
      assert_raise RuntimeError, ~r/parse error/, fn ->
        OxcEx.parse!("const = ;", "bad.js")
      end
    end
  end

  describe "valid?/2" do
    test "returns true for valid code" do
      assert OxcEx.valid?("const x = 1", "test.js")
    end

    test "returns false for invalid code" do
      refute OxcEx.valid?("const = ;", "bad.js")
    end

    test "validates TypeScript" do
      assert OxcEx.valid?("const x: number = 42", "test.ts")
    end

    test "validates JSX" do
      assert OxcEx.valid?("<App />", "test.jsx")
    end
  end

  describe "walk/2" do
    test "visits all nodes with type" do
      {:ok, ast} = OxcEx.parse("const x = 1; const y = 2;", "test.js")
      names = collect_identifiers(ast)
      assert "x" in names
      assert "y" in names
    end

    test "walks nested structures" do
      {:ok, ast} = OxcEx.parse("const obj = {a: {b: 1}}", "test.js")

      OxcEx.walk(ast, fn node ->
        send(self(), {:type, node.type})
      end)

      types = collect_messages(:type)
      assert "Program" in types
      assert "VariableDeclaration" in types
      assert "ObjectExpression" in types
    end
  end

  describe "collect/2" do
    test "collects matching nodes" do
      {:ok, ast} = OxcEx.parse("import a from 'a'; import b from 'b'; const x = 1;", "test.js")

      imports =
        OxcEx.collect(ast, fn
          %{type: "ImportDeclaration"} = node -> {:keep, node}
          _ -> :skip
        end)

      assert length(imports) == 2
      assert Enum.all?(imports, &(&1.type == "ImportDeclaration"))
    end

    test "collects identifiers" do
      {:ok, ast} = OxcEx.parse("const x = y + z", "test.js")

      names =
        OxcEx.collect(ast, fn
          %{type: "Identifier", name: name} -> {:keep, name}
          _ -> :skip
        end)

      assert "x" in names
      assert "y" in names
      assert "z" in names
    end

    test "returns empty list when nothing matches" do
      {:ok, ast} = OxcEx.parse("const x = 1", "test.js")

      result =
        OxcEx.collect(ast, fn
          %{type: "ImportDeclaration"} = node -> {:keep, node}
          _ -> :skip
        end)

      assert result == []
    end
  end

  describe "transform/3" do
    test "strips TypeScript types" do
      {:ok, js} = OxcEx.transform("const x: number = 42", "test.ts")
      assert js =~ "const x = 42"
      refute js =~ "number"
    end

    test "strips interface declarations" do
      {:ok, js} = OxcEx.transform("interface Foo { bar: string }\nconst x = 1", "test.ts")
      assert js =~ "const x = 1"
      refute js =~ "interface"
    end

    test "transforms JSX with automatic runtime" do
      {:ok, js} = OxcEx.transform("<div>hello</div>", "test.jsx")
      assert js =~ "jsx"
      refute js =~ "<div>"
    end

    test "transforms JSX with classic runtime" do
      {:ok, js} = OxcEx.transform("<div>hello</div>", "test.jsx", jsx: :classic)
      assert js =~ "createElement"
      refute js =~ "<div>"
    end

    test "transforms TSX" do
      {:ok, js} = OxcEx.transform("const el: JSX.Element = <App />", "test.tsx")
      refute js =~ "JSX.Element"
      assert js =~ "jsx" or js =~ "createElement"
    end

    test "preserves plain JS unchanged" do
      {:ok, js} = OxcEx.transform("const x = 1 + 2", "test.js")
      assert js =~ "const x = 1 + 2"
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OxcEx.transform("const = ;", "bad.ts")
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "handles enum transformation" do
      {:ok, js} = OxcEx.transform("enum Color { Red, Green, Blue }", "test.ts")
      refute js =~ "enum"
      assert js =~ "Red"
    end

    test "strips type-only imports" do
      {:ok, js} = OxcEx.transform("import type { Foo } from 'bar'", "test.ts")
      refute js =~ "import"
    end
  end

  describe "transform!/3" do
    test "returns code on success" do
      js = OxcEx.transform!("const x: number = 42", "test.ts")
      assert js =~ "const x = 42"
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/transform error/, fn ->
        OxcEx.transform!("const = ;", "bad.ts")
      end
    end
  end

  describe "minify/3" do
    test "minifies JavaScript" do
      {:ok, min} = OxcEx.minify("const x = 1 + 2;\nconsole.log(x);", "test.js")
      assert byte_size(min) < byte_size("const x = 1 + 2;\nconsole.log(x);")
      assert min =~ "console.log"
    end

    test "folds constants" do
      {:ok, min} = OxcEx.minify("const x = 1 + 2; console.log(x);", "test.js")
      assert min =~ "3"
    end

    test "mangles variable names by default" do
      {:ok, min} =
        OxcEx.minify(
          "function hello() { const longVariableName = 42; return longVariableName; }",
          "test.js"
        )

      refute min =~ "longVariableName"
    end

    test "preserves variable names with mangle: false" do
      {:ok, min} =
        OxcEx.minify("function hello(longName) { return longName; }", "test.js", mangle: false)

      assert min =~ "longName"
    end

    test "removes dead code" do
      {:ok, min} =
        OxcEx.minify("if (false) { console.log('dead') } console.log('alive')", "test.js")

      refute min =~ "dead"
      assert min =~ "alive"
    end

    test "removes whitespace and newlines" do
      source = "const   x   =   1;\n\n\nconst   y   =   2;"
      {:ok, min} = OxcEx.minify(source, "test.js")
      refute min =~ "   "
      refute min =~ "\n\n"
    end

    test "returns errors for invalid syntax" do
      {:error, errors} = OxcEx.minify("const = ;", "bad.js")
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "handles empty input" do
      {:ok, min} = OxcEx.minify("", "test.js")
      assert min == ""
    end
  end

  describe "minify!/3" do
    test "returns code on success" do
      min = OxcEx.minify!("const x = 1 + 2;", "test.js")
      assert is_binary(min)
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/minify error/, fn ->
        OxcEx.minify!("const = ;", "bad.js")
      end
    end
  end

  defp collect_identifiers(ast) do
    OxcEx.collect(ast, fn
      %{type: "Identifier", name: name} -> {:keep, name}
      _ -> :skip
    end)
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
