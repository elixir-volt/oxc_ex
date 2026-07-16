defmodule OXC.Codegen.LintTypes do
  @moduledoc false

  use RustQ.Native,
    build: false,
    load: false,
    crate: :oxc_lint_native_types

  alias RustQ.Type, as: R

  @type lint_input :: %{
          required(:plugins) => [String.t()],
          required(:rules) => [{String.t(), String.t()}],
          required(:envs) => [{String.t(), boolean()}],
          required(:globals) => [{String.t(), String.t()}],
          required(:fix) => boolean()
        }

  @type diagnostic :: %{
          required(:rule) => String.t(),
          required(:message) => String.t(),
          required(:severity) => R.path(:Atom),
          required(:span) => {R.u32(), R.u32()},
          required(:labels) => [{R.u32(), R.u32()}],
          required(:help) => String.t() | nil
        }
end
