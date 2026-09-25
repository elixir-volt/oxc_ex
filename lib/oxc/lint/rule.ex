defmodule OXC.Lint.Rule do
  @moduledoc """
  Behaviour for custom lint rules in Elixir.

  Rules receive the parsed ESTree AST (from `OXC.parse/2`) and return
  findings located by AST node `start` and `end` offsets. Use `OXC.walk/2`, `OXC.collect/2`, or `OXC.postwalk/3`
  for traversal.

  ## Example

      defmodule MyApp.NoConsoleLog do
        @behaviour OXC.Lint.Rule

        @impl true
        def meta do
          %{
            name: "my-app/no-console-log",
            description: "Disallow console.log in production code",
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
              {:keep, %{start: start, end: stop, message: "Unexpected console.log"}}

            _ ->
              :skip
          end)
        end
      end
  """

  @type meta :: %{
          name: String.t(),
          description: String.t(),
          category:
            :correctness | :suspicious | :pedantic | :perf | :style | :restriction | :nursery,
          fixable: boolean()
        }

  @type context :: %{
          source: String.t(),
          filename: String.t(),
          settings: map()
        }

  @typedoc """
  A finding reported by a rule, located by the byte `start` and `end` offsets of an AST node.

  `OXC.Lint.run/3` turns findings into `t:OXC.Diagnostic.t/0` maps.
  """
  @type diagnostic :: %{
          required(:start) => non_neg_integer(),
          required(:end) => non_neg_integer(),
          required(:message) => String.t(),
          optional(:help) => String.t() | nil,
          optional(:labels) => [
            %{
              required(:start) => non_neg_integer(),
              required(:end) => non_neg_integer(),
              optional(:message) => String.t()
            }
          ]
        }

  @callback meta() :: meta()
  @callback run(ast :: map(), context :: context()) :: [diagnostic()]
end
