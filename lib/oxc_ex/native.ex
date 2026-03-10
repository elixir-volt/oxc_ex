defmodule OxcEx.Native do
  use Rustler, otp_app: :oxc_ex, crate: "oxc_ex_nif"

  @spec parse(String.t(), String.t()) :: {:ok, map()} | {:error, list()}
  def parse(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)

  @spec valid(String.t(), String.t()) :: boolean()
  def valid(_source, _filename), do: :erlang.nif_error(:nif_not_loaded)
end
