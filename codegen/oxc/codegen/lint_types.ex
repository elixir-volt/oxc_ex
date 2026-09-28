defmodule OXC.Codegen.LintTypes do
  @moduledoc false

  use RustQ.Native,
    build: false,
    load: false,
    crate: :oxc_lint_native_types

  alias RustQ.Type, as: R

  @type rule_severity :: :allow | :warn | :deny
  @type finding_severity :: :error | :warning
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

  @type lint_input :: %{
          required(:plugins) => [plugin()],
          required(:rules) => [{String.t(), rule_severity()}],
          required(:envs) => [String.t()],
          required(:globals) => [{String.t(), global_access()}],
          required(:fix) => boolean()
        }

  @type diagnostic :: %{
          required(:rule) => String.t(),
          required(:message) => String.t(),
          required(:severity) => finding_severity(),
          required(:labels) => [{R.u32(), R.u32(), String.t() | nil}],
          required(:help) => String.t() | nil,
          required(:fixes) => [{R.u32(), R.u32(), String.t()}]
        }

  @type parse_error :: %{
          required(:message) => String.t(),
          required(:labels) => [{R.u32(), R.u32(), String.t() | nil}],
          required(:help) => String.t() | nil
        }
end
