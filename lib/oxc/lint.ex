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

  @typedoc "Rule severity in lint options. Findings report `:error` for `:deny` and `:warning` for `:warn`."
  @type severity :: :allow | :warn | :deny
  @type diagnostic :: OXC.Diagnostic.t()
  @type global_access :: :readonly | :writable | :off
  @type plugin ::
          :react
          | :unicorn
          | :typescript
          | :oxc
          | :import
          | :jsdoc
          | :jest
          | :vitest
          | :jsx_a11y
          | :nextjs
          | :react_perf
          | :promise
          | :node
          | :vue

  @type option ::
          {:rules, %{String.t() => severity()}}
          | {:plugins, [plugin()]}
          | {:env, [String.t()]}
          | {:globals, %{String.t() => global_access()}}
          | {:fix, boolean()}
          | {:custom_rules, [{module(), severity()}]}
          | {:settings, map()}

  @doc """
  Lint source code with oxlint's built-in rules and optional custom rules.

  Pass a list of files with `type_aware: true` to run TypeScript type-aware
  rules through `tsgolint` headless mode:

      OXC.Lint.run(["lib/app.ts"],
        type_aware: true,
        tsgolint: "tsgolint",
        rules: %{"typescript/no-floating-promises" => :deny})

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

    * `:env` — list of enabled Oxlint environment names, for example
      `["browser", "node", "mocha"]`.

    * `:globals` — map of global names to `:readonly`, `:writable`, or `:off`,
      for example `%{"jQuery" => :readonly}`.

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
  @spec run([String.t()], [OXC.Lint.TypeAware.option()]) ::
          {:ok, [diagnostic()]} | {:error, [diagnostic()]}
  @spec run(iodata(), String.t(), [option()]) :: {:ok, [diagnostic()]} | {:error, [diagnostic()]}
  def run(files, opts) when is_list(files) and is_list(opts) do
    if Keyword.get(opts, :type_aware, false) do
      OXC.Lint.TypeAware.run(files, opts)
    else
      {:error,
       OXC.Diagnostic.from_raw(
         ["OXC.Lint.run/2 with a file list requires type_aware: true"],
         nil,
         nil
       )}
    end
  end

  def run(source, filename, opts \\ []) do
    source = IO.iodata_to_binary(source)
    custom_rules = Keyword.get(opts, :custom_rules, [])
    settings = Keyword.get(opts, :settings, %{})

    input = %{
      plugins: Keyword.get(opts, :plugins, []),
      rules: opts |> Keyword.get(:rules, %{}) |> Map.to_list(),
      envs: Keyword.get(opts, :env, []),
      globals: opts |> Keyword.get(:globals, %{}) |> Map.to_list(),
      fix: Keyword.get(opts, :fix, false)
    }

    case OXC.Lint.Native.lint(source, filename, input) do
      {:ok, builtin} ->
        custom = run_custom_rules(custom_rules, source, filename, settings)
        {:ok, OXC.Diagnostic.from_raw(builtin ++ custom, filename, source)}

      {:error, errors} ->
        {:error, OXC.Diagnostic.from_raw(errors, filename, source)}
    end
  end

  @doc """
  Like `run/3` but raises on errors.
  """
  @spec run!(iodata(), String.t(), [option()]) :: [diagnostic()]
  def run!(source, filename, opts \\ []) do
    source |> run(filename, opts) |> OXC.Error.unwrap!()
  end

  defp run_custom_rules([], _source, _filename, _settings), do: []

  defp run_custom_rules(rules, source, filename, settings) do
    case OXC.parse(source, filename) do
      {:ok, ast} ->
        context = %{source: source, filename: filename, settings: settings}

        for {module, severity} <- rules,
            severity != :allow,
            finding <- module.run(ast, context) do
          custom_finding(finding, module.meta().name, severity)
        end

      {:error, _} ->
        []
    end
  end

  defp custom_finding(finding, rule, severity) do
    %{
      rule: rule,
      message: finding.message,
      severity: if(severity == :deny, do: :error, else: :warning),
      help: Map.get(finding, :help),
      labels: [
        {finding.start, finding.end, nil} | Enum.map(Map.get(finding, :labels, []), &label/1)
      ]
    }
  end

  defp label(%{start: start, end: stop} = label), do: {start, stop, Map.get(label, :message)}
end
