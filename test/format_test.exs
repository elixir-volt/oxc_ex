defmodule OXC.FormatTest do
  use ExUnit.Case, async: true

  describe "format/3" do
    test "formats messy JavaScript" do
      {:ok, code} = OXC.Format.format("const   x=1;let   y =  2;", "test.js")
      assert code == "const x = 1;\nlet y = 2;\n"
    end

    test "formats TypeScript" do
      {:ok, code} = OXC.Format.format("const x:number=42", "test.ts")
      assert code == "const x: number = 42;\n"
    end

    test "formats JSX" do
      {:ok, code} = OXC.Format.format("const el=<div className='foo'  >hello</div>", "test.jsx")
      assert String.contains?(code, "<div")
    end

    test "semi: false removes semicolons" do
      {:ok, code} = OXC.Format.format("const x = 1;", "test.js", semi: false)
      assert code == "const x = 1\n"
    end

    test "single_quote: true uses single quotes" do
      {:ok, code} = OXC.Format.format(~s|const x = "hello"|, "test.js", single_quote: true)
      assert code == "const x = 'hello';\n"
    end

    test "use_tabs: true indents with tabs" do
      {:ok, code} = OXC.Format.format("if(true){x()}", "test.js", use_tabs: true)
      assert String.contains?(code, "\t")
    end

    test "print_width wraps long lines" do
      input = "const obj = { alpha: 1, beta: 2, gamma: 3, delta: 4 }"
      {:ok, narrow} = OXC.Format.format(input, "test.js", print_width: 30)
      {:ok, wide} = OXC.Format.format(input, "test.js", print_width: 120)
      assert String.contains?(narrow, "\n  ")
      refute String.contains?(String.trim(wide), "\n  ")
    end

    test "returns error on invalid syntax" do
      {:error, errors} = OXC.Format.format("const = ;", "test.js")
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "trailing_comma: :none removes trailing commas" do
      {:ok, code} =
        OXC.Format.format("const a = [\n1,\n2,\n3,\n]", "test.js", trailing_comma: :none)

      refute String.contains?(code, "3,")
    end

    test "bracket_spacing: false removes spaces in objects" do
      {:ok, code} = OXC.Format.format("const x = { a: 1 }", "test.js", bracket_spacing: false)
      assert String.contains?(code, "{a: 1}")
    end

    test "arrow_parens: :avoid removes parens from single-arg arrows" do
      {:ok, code} = OXC.Format.format("const f = (x) => x", "test.js", arrow_parens: :avoid)
      assert String.contains?(code, "x => x")
    end

    test "single_attribute_per_line forces one attribute per line" do
      input = ~s|const el = <div className="a" id="b" data-x="c">hi</div>|

      {:ok, multi} =
        OXC.Format.format(input, "test.jsx", single_attribute_per_line: true, print_width: 80)

      {:ok, auto} =
        OXC.Format.format(input, "test.jsx", single_attribute_per_line: false, print_width: 80)

      assert String.split(multi, "\n") |> length() > String.split(auto, "\n") |> length()
    end

    test "experimental_operator_position option is accepted" do
      input = "const x = aaaaaaaaaa + bbbbbbbbbb + cccccccccc + dddddddddd + eeeeeeeeee"

      {:ok, code} =
        OXC.Format.format(input, "test.js",
          experimental_operator_position: :start,
          print_width: 40
        )

      assert String.contains?(code, "aaaaaaaaaa")
    end

    test "embedded_language_formatting: :off disables embedded formatting" do
      {:ok, code} =
        OXC.Format.format("const x = 1", "test.js", embedded_language_formatting: :off)

      assert String.contains?(code, "const x = 1")
    end

    test "sort_imports: true sorts imports" do
      input = "import z from 'z'\nimport a from 'a'\n"
      {:ok, code} = OXC.Format.format(input, "test.js", sort_imports: true)
      assert String.trim(code) |> String.starts_with?("import a")
    end

    test "sort_imports with options" do
      input = "import z from 'z'\nimport a from 'a'\n"
      {:ok, code} = OXC.Format.format(input, "test.js", sort_imports: %{order: :desc})
      assert String.trim(code) |> String.starts_with?("import z")
    end

    test "object_wrap: :collapse collapses short objects" do
      input = "const x = {\n  a: 1\n}"
      {:ok, collapsed} = OXC.Format.format(input, "test.js", object_wrap: :collapse)
      refute String.contains?(collapsed, "\n  a:")
    end
  end

  describe "format!/3" do
    test "returns formatted code directly" do
      code = OXC.Format.format!("const   x=1", "test.js")
      assert code == "const x = 1;\n"
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        OXC.Format.format!("const = ;", "test.js")
      end
    end
  end
end
