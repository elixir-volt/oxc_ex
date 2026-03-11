defmodule OxcEx do
  @moduledoc """
  Elixir bindings for the OXC JavaScript toolchain.

  Provides fast JavaScript and TypeScript parsing, transformation, and
  minification via OXC's Rust toolchain. The file extension determines
  the dialect — `.js`, `.jsx`, `.ts`, `.tsx`.

      {:ok, ast} = OxcEx.parse("const x = 1 + 2", "test.js")
      ast.type  # "Program"

      {:ok, js} = OxcEx.transform("const x: number = 42", "test.ts")
      # "const x = 42;\\n"

      {:ok, min} = OxcEx.minify("const x = 1 + 2; console.log(x);", "test.js")

  AST nodes are maps with atom keys, following the ESTree specification.
  """

  @type ast :: map()
  @type error :: %{message: String.t()}
  @type parse_result :: {:ok, ast()} | {:error, [error()]}

  @doc """
  Parse JavaScript or TypeScript source code into an ESTree AST.

  The filename extension determines the dialect:
  - `.js` — JavaScript
  - `.jsx` — JavaScript with JSX
  - `.ts` — TypeScript
  - `.tsx` — TypeScript with JSX

  Returns `{:ok, ast}` where `ast` is a map with atom keys, or
  `{:error, errors}` with a list of parse error maps.

  ## Examples

      {:ok, ast} = OxcEx.parse("const x = 1", "test.js")
      [%{type: "VariableDeclaration"}] = ast.body

      {:error, errors} = OxcEx.parse("const = ;", "bad.js")
  """
  @spec parse(String.t(), String.t()) :: parse_result()
  def parse(source, filename) do
    OxcEx.Native.parse(source, filename)
  end

  @doc """
  Like `parse/2` but raises on parse errors.

      ast = OxcEx.parse!("const x = 1", "test.js")
  """
  @spec parse!(String.t(), String.t()) :: ast()
  def parse!(source, filename) do
    case parse(source, filename) do
      {:ok, ast} -> ast
      {:error, errors} -> raise "OXC parse error: #{inspect(errors)}"
    end
  end

  @doc """
  Check if source code is syntactically valid.

  Faster than `parse/2` — skips AST serialization.

      OxcEx.valid?("const x = 1", "test.js")  # true
      OxcEx.valid?("const = ;", "bad.js")      # false
  """
  @spec valid?(String.t(), String.t()) :: boolean()
  def valid?(source, filename) do
    OxcEx.Native.valid(source, filename)
  end

  @doc """
  Transform TypeScript/JSX source code into plain JavaScript.

  Strips type annotations, transforms JSX, and lowers syntax features.
  The filename extension determines the source dialect.

  ## Options

    * `:jsx` — JSX runtime, `:automatic` (default) or `:classic`

  ## Examples

      {:ok, js} = OxcEx.transform("const x: number = 42", "test.ts")

      {:ok, js} = OxcEx.transform("<App />", "app.tsx", jsx: :classic)
  """
  @spec transform(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, [String.t()]}
  def transform(source, filename, opts \\ []) do
    jsx_runtime = opts |> Keyword.get(:jsx, :automatic) |> Atom.to_string()
    OxcEx.Native.transform(source, filename, jsx_runtime)
  end

  @doc """
  Like `transform/3` but raises on errors.
  """
  @spec transform!(String.t(), String.t(), keyword()) :: String.t()
  def transform!(source, filename, opts \\ []) do
    case transform(source, filename, opts) do
      {:ok, code} -> code
      {:error, errors} -> raise "OXC transform error: #{inspect(errors)}"
    end
  end

  @doc """
  Minify JavaScript source code.

  Applies dead code elimination, constant folding, and whitespace removal.
  Optionally mangles variable names for smaller output.

  ## Options

    * `:mangle` — rename variables for shorter names (default: `true`)

  ## Examples

      {:ok, min} = OxcEx.minify("const x = 1 + 2; console.log(x);", "test.js")

      {:ok, min} = OxcEx.minify("const longName = 1;", "test.js", mangle: false)
  """
  @spec minify(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, [String.t()]}
  def minify(source, filename, opts \\ []) do
    mangle = Keyword.get(opts, :mangle, true)
    OxcEx.Native.minify(source, filename, mangle)
  end

  @doc """
  Like `minify/3` but raises on errors.
  """
  @spec minify!(String.t(), String.t(), keyword()) :: String.t()
  def minify!(source, filename, opts \\ []) do
    case minify(source, filename, opts) do
      {:ok, code} -> code
      {:error, errors} -> raise "OXC minify error: #{inspect(errors)}"
    end
  end

  @doc """
  Walk an AST tree, calling `fun` on every node (any map with a `type` key).

  ## Examples

      {:ok, ast} = OxcEx.parse("const x = 1; let y = 2", "test.js")
      OxcEx.walk(ast, fn
        %{type: "Identifier", name: name} -> IO.puts(name)
        _ -> :ok
      end)
  """
  @spec walk(ast(), (map() -> any())) :: :ok
  def walk(node, fun) when is_map(node) do
    if Map.has_key?(node, :type), do: fun.(node)

    node
    |> Map.values()
    |> Enum.each(fn
      child when is_map(child) -> walk(child, fun)
      children when is_list(children) -> Enum.each(children, &walk_child(&1, fun))
      _ -> :ok
    end)
  end

  def walk(_node, _fun), do: :ok

  defp walk_child(node, fun) when is_map(node), do: walk(node, fun)
  defp walk_child(_node, _fun), do: :ok

  @doc """
  Collect AST nodes that match a filter function.

  The function receives each node (map with `type` key) and should return
  `{:keep, value}` to include it in results, or `:skip` to exclude it.

  ## Examples

      {:ok, ast} = OxcEx.parse("import a from 'a'; import b from 'b'", "test.js")
      imports = OxcEx.collect(ast, fn
        %{type: "ImportDeclaration"} = node -> {:keep, node}
        _ -> :skip
      end)
      length(imports)  # 2
  """
  @spec collect(ast(), (map() -> {:keep, any()} | :skip)) :: [any()]
  def collect(node, fun) do
    acc = :ets.new(:oxc_collect, [:set, :private])

    try do
      walk(node, fn n ->
        case fun.(n) do
          {:keep, value} -> :ets.insert(acc, {:erlang.unique_integer([:monotonic]), value})
          :skip -> :ok
        end
      end)

      acc
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    after
      :ets.delete(acc)
    end
  end
end
