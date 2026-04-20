defmodule OXC.Lint.Native do
  @moduledoc false

  use Rustler,
    otp_app: :oxc,
    crate: "oxc_lint_nif",
    path: "native/oxc_lint_nif",
    cargo: :system

  @spec lint(String.t(), String.t(), [String.t()], [{String.t(), String.t()}], boolean()) ::
          {:ok, [map()]} | {:error, [String.t()]}
  def lint(_source, _filename, _plugins, _rules, _fix), do: :erlang.nif_error(:nif_not_loaded)
end
