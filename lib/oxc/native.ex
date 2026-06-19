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
  def parse(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)

  @spec valid(iodata(), String.t()) :: boolean()
  def valid(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)

  @spec transform(iodata(), String.t(), map()) :: {:ok, String.t() | map()} | {:error, list()}
  def transform(_source, _filename, _opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec minify(iodata(), String.t(), map()) :: {:ok, String.t()} | {:error, list()}
  def minify(_source, _filename, _opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec bundle([{String.t(), iodata()}], map()) ::
          {:ok, String.t() | map()} | {:error, [String.t()]}
  def bundle(_files, _opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec bundle_entry(String.t(), map()) :: {:ok, String.t() | map()} | {:error, [String.t()]}
  def bundle_entry(_entry, _opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec bundle_run(map()) :: {:ok, map()} | {:error, [map()]}
  def bundle_run(_opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec select(iodata(), String.t(), list()) :: {:ok, list()} | {:error, [String.t()]}
  def select(_source, _filename, _spec), do: :erlang.nif_error(:nif_not_loaded)

  @spec transform_many([{iodata(), String.t()}], map()) :: list()
  def transform_many(_inputs, _opts), do: :erlang.nif_error(:nif_not_loaded)

  @spec codegen(map()) :: {:ok, String.t()} | {:error, list()}
  def codegen(_ast), do: :erlang.nif_error(:nif_not_loaded)
end
