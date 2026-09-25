defmodule OXC.Diagnostic do
  @moduledoc """
  Errors and lint findings as Elixir `t:Code.diagnostic/1` maps.

  Every OXC error and lint finding uses this shape:

      %{
        file: "app.ts",
        severity: :error,
        message: "Unexpected token",
        position: {2, 11},
        span: {2, 12},
        source: nil,
        stacktrace: []
      }

  `position` is the 1-based `{line, column}` where the problem starts and `span`
  is where it ends, with columns counted in characters. Diagnostics without a
  source location use `position: 0` and `span: nil`, as Elixir does.

  Some diagnostics carry extra keys:

    * `:details` — help text suggesting a fix
    * `:rule` — the lint rule that reported the finding
    * `:labels` — secondary locations, each with `:position`, `:span`, and `:message`
    * `:fixes` — lint fixes as `t:OXC.patch/0` maps, ready for `OXC.patch_string/2`
    * `:suggestions` — alternative type-aware fixes, each with a `:message` and `:fixes`
  """

  @type position :: {line :: pos_integer(), column :: pos_integer()}
  @type label :: %{position: position(), span: position(), message: String.t() | nil}
  @type t :: Code.diagnostic(:error | :warning)

  @typedoc "A native error: message, help, and byte-range labels with the primary label first."
  @type raw :: %{
          required(:message) => String.t(),
          optional(:help) => String.t() | nil,
          optional(:labels) => [{non_neg_integer(), non_neg_integer(), String.t() | nil}],
          optional(:severity) => :error | :warning,
          optional(:rule) => String.t(),
          optional(:fixes) => [{non_neg_integer(), non_neg_integer(), String.t()}],
          optional(:suggestions) => [
            %{message: String.t(), fixes: [{non_neg_integer(), non_neg_integer(), String.t()}]}
          ],
          optional(atom()) => term()
        }

  @doc """
  Build diagnostics from native errors reported for `source` in `file`.

  Pass `nil` for `source` when the errors do not refer to a single source text.
  """
  @spec from_raw([raw() | String.t()], String.t() | nil, iodata() | nil) :: [t()]
  def from_raw(errors, file, source) do
    source = source && IO.iodata_to_binary(source)
    lines = source && line_starts(source)
    Enum.map(errors, &diagnostic(&1, file, source, lines))
  end

  @doc """
  Format a diagnostic as `file:line:column: message`, like Elixir compiler output.
  """
  @spec format(t()) :: String.t()
  def format(%{file: file, position: {line, column}, message: message}) when is_binary(file),
    do: "#{file}:#{line}:#{column}: #{message}"

  def format(%{file: file, message: message}) when is_binary(file), do: "#{file}: #{message}"
  def format(%{message: message}), do: message

  defp diagnostic(message, file, source, lines) when is_binary(message),
    do: diagnostic(%{message: message}, file, source, lines)

  defp diagnostic(raw, file, source, lines) do
    {primary, secondary} =
      case Map.get(raw, :labels, []) do
        [primary | secondary] when is_binary(source) -> {primary, secondary}
        _labels -> {nil, []}
      end

    %{
      source: nil,
      file: file,
      severity: Map.get(raw, :severity, :error),
      message: raw.message,
      position: 0,
      span: nil,
      stacktrace: []
    }
    |> put_range(primary, source, lines)
    |> put_present(:details, Map.get(raw, :help))
    |> put_present(:rule, Map.get(raw, :rule))
    |> put_present(:labels, Enum.map(secondary, &label(&1, source, lines)))
    |> put_present(:fixes, Enum.map(Map.get(raw, :fixes, []), &fix/1))
    |> put_present(:suggestions, Enum.map(Map.get(raw, :suggestions, []), &suggestion/1))
  end

  defp put_range(diagnostic, nil, _source, _lines), do: diagnostic

  defp put_range(diagnostic, {start, stop, _message}, source, lines) do
    %{diagnostic | position: position(source, lines, start), span: position(source, lines, stop)}
  end

  defp label({start, stop, message}, source, lines) do
    %{
      position: position(source, lines, start),
      span: position(source, lines, stop),
      message: message
    }
  end

  # Fixes are `t:OXC.patch/0` maps, so `OXC.patch_string/2` applies them directly.
  defp fix({start, stop, change}), do: %{start: start, end: stop, change: change}

  defp suggestion(%{message: message, fixes: fixes}),
    do: %{message: message, fixes: Enum.map(fixes, &fix/1)}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, _key, []), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp line_starts(source) do
    newlines = for {offset, 1} <- :binary.matches(source, "\n"), do: offset + 1
    List.to_tuple([0 | newlines])
  end

  defp position(source, lines, offset) do
    offset = min(offset, byte_size(source))
    line = line_index(lines, offset, 0, tuple_size(lines) - 1)
    start = elem(lines, line)
    {line + 1, codepoints(binary_part(source, start, offset - start)) + 1}
  end

  defp line_index(_lines, _offset, low, high) when low >= high, do: low

  defp line_index(lines, offset, low, high) do
    middle = div(low + high + 1, 2)

    if elem(lines, middle) <= offset,
      do: line_index(lines, offset, middle, high),
      else: line_index(lines, offset, low, middle - 1)
  end

  # Count UTF-8 lead bytes so offsets inside a character never raise.
  defp codepoints(binary),
    do:
      for(<<byte <- binary>>, Bitwise.band(byte, 0xC0) != 0x80,
        reduce: 0,
        do: (count -> count + 1)
      )
end
