defmodule OXC.Lint do
  @moduledoc """
  Lint JavaScript/TypeScript source with oxlint's built-in rules
  and optional custom Elixir rules.

  Combines native Rust performance for 650+ standard rules with
  the ability to write project-specific rules in Elixir using
  the same AST that `OXC.parse/2` returns.

  ## Examples

      {:ok, diags} = OXC.Lint.run("debugger;", "test.js",
        rules: %{"no-debugger" => :deny})

      {:ok, []} = OXC.Lint.run("export const x = 1;\\n", "test.ts")
  """

  @type severity :: :allow | :warn | :deny
  @type diagnostic :: %{
          rule: String.t(),
          message: String.t(),
          severity: severity(),
          span: {non_neg_integer(), non_neg_integer()},
          labels: [{non_neg_integer(), non_neg_integer()}],
          help: String.t() | nil
        }

  @doc """
  Lint source code with oxlint's built-in rules and optional custom rules.

  ## Options

    * `:rules` — map of rule names to severity (`:deny`, `:warn`, `:allow`).
      Rule names follow oxlint conventions: `"eqeqeq"`, `"react/no-danger"`,
      `"typescript/no-explicit-any"`, etc.

    * `:plugins` — list of built-in plugin atoms to enable.
      Default: oxlint defaults (eslint correctness rules).
      Available: `:react`, `:typescript`, `:unicorn`, `:import`, `:jsdoc`,
      `:jest`, `:vitest`, `:jsx_a11y`, `:nextjs`, `:react_perf`, `:promise`,
      `:node`, `:vue`, `:oxc`

    * `:fix` — compute fix suggestions. Default: `false`

    * `:custom_rules` — list of `{module, severity}` tuples for Elixir rules.
      Each module must implement the `OXC.Lint.Rule` behaviour.

    * `:settings` — arbitrary map passed to custom rule context.

  ## Examples

      # Built-in rules only
      {:ok, diags} = OXC.Lint.run("debugger;", "test.js",
        rules: %{"no-debugger" => :deny})

      # With specific plugins and rules
      {:ok, diags} = OXC.Lint.run(source, "app.tsx",
        plugins: [:react, :typescript],
        rules: %{"no-console" => :warn, "react/no-danger" => :deny}
      )

      # With custom Elixir rules
      {:ok, diags} = OXC.Lint.run(source, "app.ts",
        custom_rules: [{MyApp.NoConsoleLog, :warn}]
      )
  """
  @spec run(String.t(), String.t(), keyword()) :: {:ok, [diagnostic()]} | {:error, [String.t()]}
  def run(source, filename, opts \\ []) do
    plugins = opts |> Keyword.get(:plugins, []) |> Enum.map(&to_string/1)
    fix = Keyword.get(opts, :fix, false)

    rules =
      opts
      |> Keyword.get(:rules, %{})
      |> Enum.map(fn {name, severity} -> {to_string(name), severity_to_string(severity)} end)

    custom_rules = Keyword.get(opts, :custom_rules, [])
    settings = Keyword.get(opts, :settings, %{})

    case OXC.Lint.Native.lint(source, filename, plugins, rules, fix) do
      {:ok, builtin_diags} ->
        custom =
          case custom_rules do
            [] -> []
            rules -> run_custom_rules(rules, source, filename, settings)
          end

        {:ok, builtin_diags ++ custom}

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp severity_to_string(:deny), do: "deny"
  defp severity_to_string(:warn), do: "warn"
  defp severity_to_string(:allow), do: "allow"

  defp run_custom_rules(rules, source, filename, settings) do
    case OXC.parse(source, filename) do
      {:ok, ast} ->
        context = %{source: source, filename: filename, settings: settings}

        Enum.flat_map(rules, fn {module, severity} ->
          meta = module.meta()

          module.run(ast, context)
          |> Enum.map(fn diag ->
            %{
              rule: meta.name,
              message: diag.message,
              severity: severity,
              span: Map.get(diag, :span, {0, 0}),
              labels: Map.get(diag, :labels, []),
              help: Map.get(diag, :help)
            }
          end)
        end)

      {:error, _} ->
        []
    end
  end
end
