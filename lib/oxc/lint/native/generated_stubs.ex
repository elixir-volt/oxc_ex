defmodule OXC.Lint.Native.GeneratedStubs do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      def lint(_source_term, _filename, _plugins, _rules, _fix) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end
