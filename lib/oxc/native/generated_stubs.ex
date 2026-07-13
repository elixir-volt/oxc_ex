defmodule OXC.Native.GeneratedStubs do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      def parse(_source_term, _filename) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def valid(_source_term, _filename) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def transform(_source_term, _filename, _opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def minify(_source_term, _filename, _opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def bundle(_files, _opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def bundle_entry(_entry, _opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def bundle_run(_opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def select(_source_term, _filename, _spec) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def transform_many(_inputs, _opts_term) do
        :erlang.nif_error(:nif_not_loaded)
      end

      def codegen(_ast) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end
