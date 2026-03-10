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
