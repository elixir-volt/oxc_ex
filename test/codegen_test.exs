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

    test "roundtrips class with methods" do
      source = "class Dog extends Animal {\n\tconstructor(name) {\n\t\tsuper(name);\n\t}\n\tbark() {\n\t\treturn \"woof\";\n\t}\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "class Dog extends Animal"
      assert js =~ "constructor(name)"
      assert js =~ "bark()"
    end

    test "roundtrips template literal" do
      source = "const x = `hello ${name}!`;\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "${name}"
    end

    test "roundtrips if/else" do
      source = "if (x > 0) {\n\ty();\n} else {\n\tz();\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "if (x > 0)"
      assert js =~ "else"
    end

    test "roundtrips for-of loop" do
      source = "for (const item of items) {\n\tconsole.log(item);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "for (const item of items)"
    end

    test "roundtrips try/catch" do
      source = "try {\n\tx();\n} catch (e) {\n\ty(e);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "try"
      assert js =~ "catch (e)"
    end

    test "roundtrips async/await" do
      source = "async function f() {\n\tconst x = await fetch(url);\n}\n"
      {:ok, ast} = OXC.parse(source, "test.js")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "async function"
      assert js =~ "await fetch"
    end

    test "roundtrips spread and rest" do
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
    test "renames identifiers" do
      {:ok, ast} = OXC.parse("const $name = $value", "t.js")
      ast = OXC.bind(ast, name: "greeting", value: "hello")
      {:ok, js} = OXC.codegen(ast)
      assert js =~ "const greeting = hello"
    end

    test "substitutes literal numbers" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, 42})
      assert OXC.codegen!(ast) =~ "const x = 42"
    end

    test "substitutes literal strings" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, "hello"})
      assert OXC.codegen!(ast) =~ ~s(const x = "hello")
    end

    test "substitutes literal booleans" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, true})
      assert OXC.codegen!(ast) =~ "const x = true"
    end

    test "substitutes literal nil as null" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, nil})
      assert OXC.codegen!(ast) =~ "const x = null"
    end

    test "substitutes literal maps as objects" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, %{port: 3000, debug: true}})
      js = OXC.codegen!(ast)
      assert js =~ "port:"
      assert js =~ "3e3" or js =~ "3000"
      assert js =~ "debug: true"
    end

    test "substitutes literal lists as arrays" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, [1, "two", true]})
      js = OXC.codegen!(ast)
      assert js =~ "1"
      assert js =~ ~s("two")
      assert js =~ "true"
    end

    test "substitutes nested literal structures" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:literal, %{user: %{name: "Joe", tags: ["admin"]}}})
      js = OXC.codegen!(ast)
      assert js =~ "user:"
      assert js =~ ~s("Joe")
      assert js =~ ~s("admin")
    end

    test "substitutes expressions with {:expr, ...}" do
      {:ok, ast} = OXC.parse("const $name = $init", "t.js")
      ast = OXC.bind(ast, name: "count", init: {:expr, "ref(0)"})
      assert OXC.codegen!(ast) =~ "const count = ref(0)"
    end

    test "substitutes complex expressions" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")
      ast = OXC.bind(ast, val: {:expr, "a > 0 ? a : -a"})
      assert OXC.codegen!(ast) =~ "a > 0 ? a : -a"
    end

    test "substitutes raw AST nodes" do
      {:ok, ast} = OXC.parse("const x = $val", "t.js")

      node = %{
        type: :binary_expression,
        operator: "+",
        left: %{type: :literal, value: 1},
        right: %{type: :literal, value: 2}
      }

      ast = OXC.bind(ast, val: node)
      assert OXC.codegen!(ast) =~ "const x = 1 + 2"
    end

    test "leaves unbound placeholders as-is" do
      {:ok, ast} = OXC.parse("const $x = $y", "t.js")
      ast = OXC.bind(ast, x: "a")
      assert OXC.codegen!(ast) =~ "const a = $y"
    end

    test "works in a pipeline" do
      js =
        OXC.parse!("const $name = $value", "t.js")
        |> OXC.bind(name: "count", value: {:literal, 0})
        |> OXC.codegen!()

      assert js =~ "const count = 0"
    end
  end

  describe "splice/3" do
    test "splices statements into function body" do
      js =
        OXC.parse!("function f() { $body }", "t.js")
        |> OXC.splice(:body, ["const x = 1;", "const y = 2;", "return x + y;"])
        |> OXC.codegen!()

      assert js =~ "const x = 1"
      assert js =~ "const y = 2"
      assert js =~ "return x + y"
    end

    test "splices a single statement" do
      js =
        OXC.parse!("function f() { $action }", "t.js")
        |> OXC.splice(:action, "return 42;")
        |> OXC.codegen!()

      assert js =~ "return 42"
    end

    test "splices object properties" do
      js =
        OXC.parse!("const obj = {a: 1, $rest}", "t.js")
        |> OXC.splice(:rest, ["b: 2", "c: 3"])
        |> OXC.codegen!()

      assert js =~ "a: 1"
      assert js =~ "b: 2"
      assert js =~ "c: 3"
    end

    test "splices array elements" do
      js =
        OXC.parse!("const arr = [$items]", "t.js")
        |> OXC.splice(:items, ["1", "\"two\"", "true"])
        |> OXC.codegen!()

      assert js =~ "1"
      assert js =~ ~s("two")
      assert js =~ "true"
    end

    test "removes placeholder with empty list" do
      js =
        OXC.parse!("function f() { $debug; return 1; }", "t.js")
        |> OXC.splice(:debug, [])
        |> OXC.codegen!()

      assert js =~ "return 1"
      refute js =~ "debug"
    end

    test "splices into program body" do
      js =
        OXC.parse!("const x = 1;\n$more", "t.js")
        |> OXC.splice(:more, ["const y = 2;", "const z = 3;"])
        |> OXC.codegen!()

      assert js =~ "const x = 1"
      assert js =~ "const y = 2"
      assert js =~ "const z = 3"
    end

    test "accepts raw AST nodes" do
      stmt = %{
        type: :variable_declaration,
        kind: :const,
        declarations: [
          %{
            type: :variable_declarator,
            id: %{type: :identifier, name: "x"},
            init: %{type: :literal, value: 99}
          }
        ]
      }

      js =
        OXC.parse!("function f() { $body }", "t.js")
        |> OXC.splice(:body, stmt)
        |> OXC.codegen!()

      assert js =~ "const x = 99"
    end

    test "full pipeline with bind and splice" do
      template = ~s|import { z } from "zod";\nexport const $schema = z.object({$fields});\n$actions\n|

      fields = ["id: z.string().uuid()", "name: z.string()"]

      actions = [
        ~s|export function listUsers() { return fetch("/api/users"); }|
      ]

      js =
        OXC.parse!(template, "t.ts")
        |> OXC.bind(schema: "userSchema")
        |> OXC.splice(:fields, fields)
        |> OXC.splice(:actions, actions)
        |> OXC.codegen!()

      assert js =~ "userSchema"
      assert js =~ "z.string().uuid()"
      assert js =~ "z.string()"
      assert js =~ "listUsers"
    end
  end
end
