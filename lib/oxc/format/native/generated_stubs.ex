defmodule OXC.Format.Native.GeneratedStubs do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      def format(_source_term, _filename, _opts) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end
