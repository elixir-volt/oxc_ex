defmodule OXC.Format.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]
  source_root = Path.expand("../../..", __DIR__)

  local_test_build =
    Mix.env() == :test and
      File.exists?(Path.join(source_root, "test/test_helper.exs")) and
      File.dir?(Path.join(source_root, ".git"))

  use RustlerPrecompiled,
    otp_app: :oxc,
    crate: "oxc_fmt_nif",
    base_url: "https://github.com/elixir-volt/oxc_ex/releases/download/v#{version}",
    force_build: local_test_build or System.get_env("OXC_EX_BUILD") in ["1", "true"],
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
    ),
    version: version

  @spec format(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, [String.t()]}
  def format(_source, _filename, _opts), do: :erlang.nif_error(:nif_not_loaded)
end
