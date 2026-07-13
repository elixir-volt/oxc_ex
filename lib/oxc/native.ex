defmodule OXC.Native do
  version = Mix.Project.config()[:version]
  source_root = Path.expand("../..", __DIR__)

  local_test_build =
    Mix.env() == :test and
      File.exists?(Path.join(source_root, "test/test_helper.exs")) and
      File.dir?(Path.join(source_root, ".git"))

  use RustlerPrecompiled,
    otp_app: :oxc,
    crate: "oxc_ex_nif",
    base_url: "https://github.com/elixir-volt/oxc_ex/releases/download/v#{version}",
    force_build: local_test_build or System.get_env("OXC_EX_BUILD") in ["1", "true"],
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    ),
    version: version

  @spec parse(iodata(), String.t()) :: {:ok, map()} | {:error, list()}
  @spec valid(iodata(), String.t()) :: boolean()
  @spec transform(iodata(), String.t(), map()) :: {:ok, String.t() | map()} | {:error, list()}
  @spec minify(iodata(), String.t(), map()) :: {:ok, String.t()} | {:error, list()}
  @spec bundle([{String.t(), iodata()}], map()) ::
          {:ok, String.t() | map()} | {:error, [String.t()]}
  @spec bundle_entry(String.t(), map()) :: {:ok, String.t() | map()} | {:error, [String.t()]}
  @spec bundle_run(map()) :: {:ok, map()} | {:error, [map()]}
  @spec select(iodata(), String.t(), list()) :: {:ok, list()} | {:error, [String.t()]}
  @spec transform_many([{iodata(), String.t()}], map()) :: list()
  @spec codegen(map()) :: {:ok, String.t()} | {:error, list()}
  use OXC.Native.GeneratedStubs
end
