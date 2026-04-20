defmodule OXC.CodegenTest do
  use ExUnit.Case, async: true

  describe "codegen/1" do
    test "roundtrips parsed code" do
      source = "const x = 1 + 2;\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js == source
    end

    test "generates from manual AST" do
      ast = %{
        type: :program,
        body: [
          %{
            type: :variable_declaration,
            kind: :const,
            declarations: [
              %{
                type: :variable_declarator,
                id: %{type: :identifier, name: "x"},
                init: %{type: :literal, value: 42}
              }
            ]
          }
        ]
      }

      assert {:ok, js} = OXC.codegen(ast)
      assert js =~ "const x = 42"
    end

    test "generates function declaration" do
      ast = %{
        type: :program,
        body: [
          %{
            type: :function_declaration,
            id: %{type: :identifier, name: "add"},
            params: [%{type: :identifier, name: "a"}, %{type: :identifier, name: "b"}],
            body: %{
              type: :block_statement,
              body: [
                %{
                  type: :return_statement,
                  argument: %{
                    type: :binary_expression,
                    operator: "+",
                    left: %{type: :identifier, name: "a"},
                    right: %{type: :identifier, name: "b"}
                  }
                }
              ]
            }
          }
        ]
      }

      assert {:ok, js} = OXC.codegen(ast)
      assert js =~ "function add(a, b)"
      assert js =~ "return a + b"
    end

    test "generates arrow function expression" do
      ast = %{
        type: :program,
        body: [
          %{
            type: :variable_declaration,
            kind: :const,
            declarations: [
              %{
                type: :variable_declarator,
                id: %{type: :identifier, name: "f"},
                init: %{
                  type: :arrow_function_expression,
                  expression: true,
                  async: false,
                  params: [%{type: :identifier, name: "x"}],
                  body: %{
                    type: :binary_expression,
                    operator: "*",
                    left: %{type: :identifier, name: "x"},
                    right: %{type: :literal, value: 2}
                  }
                }
              }
            ]
          }
        ]
      }

      assert {:ok, js} = OXC.codegen(ast)
      assert js =~ "=> x * 2"
    end

    test "generates import declaration" do
      ast = %{
        type: :program,
        body: [
          %{
            type: :import_declaration,
            source: %{type: :literal, value: "vue"},
            specifiers: [
              %{
                type: :import_specifier,
                local: %{type: :identifier, name: "ref"},
                imported: %{type: :identifier, name: "ref"}
              }
            ]
          }
        ]
      }

      assert {:ok, js} = OXC.codegen(ast)
      assert js =~ ~s(import { ref } from "vue")
    end

    test "generates export default" do
      ast = %{
        type: :program,
        body: [
          %{type: :export_default_declaration, declaration: %{type: :literal, value: 42}}
        ]
      }

      assert {:ok, js} = OXC.codegen(ast)
      assert js =~ "export default 42"
    end

    test "generates class with methods" do
      source = "class Dog extends Animal {\n\tconstructor(name) {\n\t\tsuper(name);\n\t}\n\tbark() {\n\t\treturn \"woof\";\n\t}\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "class Dog extends Animal"
      assert js =~ "constructor(name)"
      assert js =~ "bark()"
    end

    test "generates template literal" do
      source = "const x = `hello ${name}!`;\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "${name}"
    end

    test "generates object expression" do
      source = "const obj = { a: 1, b: \"two\" };\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "a: 1"
      assert js =~ ~s(b: "two")
    end

    test "generates if/else" do
      source = "if (x > 0) {\n\ty();\n} else {\n\tz();\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "if (x > 0)"
      assert js =~ "else"
    end

    test "generates for-of loop" do
      source = "for (const item of items) {\n\tconsole.log(item);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "for (const item of items)"
    end

    test "generates try/catch" do
      source = "try {\n\tx();\n} catch (e) {\n\ty(e);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "try"
      assert js =~ "catch (e)"
    end

    test "generates async/await" do
      source = "async function f() {\n\tconst x = await fetch(url);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "async function"
      assert js =~ "await fetch"
    end

    test "generates spread and rest" do
      source = "const [first, ...rest] = items;\nconst merged = { ...a, ...b };\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "...rest"
      assert js =~ "...a"
    end

    test "returns error for invalid AST" do
      assert {:error, _} = OXC.codegen(%{type: :program, body: [%{type: :invalid_type}]})
    end
  end

  describe "codegen!/1" do
    test "returns code on success" do
      {:ok, ast} = OXC.parse("const x = 1", "test.js")
      assert is_binary(OXC.codegen!(ast))
    end

    test "raises on error" do
      assert_raise OXC.Error, ~r/codegen error/, fn ->
        OXC.codegen!(%{type: :program, body: [%{type: :invalid_type}]})
      end
    end
  end

  describe "bind/2" do
    test "substitutes identifier placeholders" do
      {:ok, ast} = OXC.parse("const $name = $value", "t.js")
      ast = OXC.bind(ast, name: "greeting", value: "hello")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "const greeting = hello"
    end

    test "substitutes literal values" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, 42})
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "const x = 42"
    end

    test "substitutes string literals" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, "hello"})
      {:ok, js} = OXC.codegen(ast)
      assert js =~ ~s(const x = "hello")
    end

    test "substitutes AST nodes" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      node = %{type: :binary_expression, operator: "+",
               left: %{type: :literal, value: 1}, right: %{type: :literal, value: 2}}
      ast = OXC.bind(ast, val: node)
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "const x = 1 + 2"
    end

    test "leaves unbound placeholders as-is" do
      {:ok, ast} = OXC.parse("const $x = $y", "t.js")
      ast = OXC.bind(ast, x: "a")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "const a = $y"
    end

    test "works with parse -> bind -> codegen pipeline" do
      js =
        OXC.parse!("const $name = $value", "t.js")
        |> OXC.bind(name: "count", value: {:literal, 0})
        |> OXC.codegen!()

      assert js =~ "const count = 0"
    end
  end
end
