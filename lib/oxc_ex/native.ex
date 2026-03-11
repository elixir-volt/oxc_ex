defmodule OxcEx.Native do
  use Rustler, otp_app: :oxc_ex, crate: "oxc_ex_nif"

  @spec parse(String.t(), String.t()) :: {:ok, map()} | {:error, list()}
  def parse(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)

  @spec valid(String.t(), String.t()) :: boolean()
  def valid(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)

  @spec transform(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, list()}
  def transform(_source, _filename, _jsx_runtime), do: :erlang.nif_error(:nif_not_loaded)

  @spec minify(String.t(), String.t(), boolean()) :: {:ok, String.t()} | {:error, list()}
  def minify(_source, _filename, _mangle), do: :erlang.nif_error(:nif_not_loaded)
end
