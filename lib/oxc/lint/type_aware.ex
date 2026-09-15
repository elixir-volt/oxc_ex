defmodule OXC.Lint.TypeAware do
  @moduledoc "Runs type-aware TypeScript lint rules through tsgolint headless mode."

  defmodule Payload do
    @moduledoc "tsgolint headless payload."

    @derive Jason.Encoder
    defstruct version: 2,
              configs: [],
              source_overrides: %{},
              report_syntactic: false,
              report_semantic: false
  end

  defmodule Config do
    @moduledoc "Files and rules submitted to tsgolint."

    @derive Jason.Encoder
    defstruct file_paths: [], rules: []
  end

  defmodule Rule do
    @moduledoc "Rule entry submitted to tsgolint."

    @derive Jason.Encoder
    defstruct name: nil, options: nil
  end

  defmodule Range do
    @moduledoc "tsgolint byte range."
    use JSONCodec, strict: true

    defstruct [:pos, :end]
    @type t :: %__MODULE__{pos: non_neg_integer(), end: non_neg_integer()}
  end

  defmodule RuleMessage do
    @moduledoc "tsgolint diagnostic message."
    use JSONCodec, strict: true

    defstruct [:id, :description, help: nil]
    @type t :: %__MODULE__{id: String.t(), description: String.t(), help: String.t() | nil}
  end

  defmodule Fix do
    @moduledoc "tsgolint text edit."
    use JSONCodec, strict: true

    defstruct [:text, :range]
    @type t :: %__MODULE__{text: String.t(), range: Range.t()}
  end

  defmodule Suggestion do
    @moduledoc "tsgolint alternative fix."
    use JSONCodec, strict: true

    defstruct [:message, fixes: []]
    @type t :: %__MODULE__{message: RuleMessage.t(), fixes: [Fix.t()]}
  end

  defmodule LabeledRange do
    @moduledoc "tsgolint secondary location."
    use JSONCodec, strict: true

    defstruct [:label, :range]
    @type t :: %__MODULE__{label: String.t(), range: Range.t()}
  end

  defmodule DiagnosticPayload do
    @moduledoc "tsgolint diagnostic frame. `:rule` findings always carry a rule, range, and file."
    use JSONCodec, strict: true

    defstruct [
      :kind,
      :message,
      range: nil,
      file_path: nil,
      rule: nil,
      fixes: [],
      suggestions: [],
      labeled_ranges: []
    ]

    @type t :: %__MODULE__{
            kind: :rule | :internal,
            message: RuleMessage.t(),
            range: Range.t() | nil,
            file_path: String.t() | nil,
            rule: String.t() | nil,
            fixes: [Fix.t()],
            suggestions: [Suggestion.t()],
            labeled_ranges: [LabeledRange.t()]
          }

    codec(:kind, cast: :kind)

    @doc "Decode tsgolint's numeric diagnostic kind: `0` for rule findings, `1` for internal diagnostics."
    def kind(0), do: {:ok, :rule}
    def kind(1), do: {:ok, :internal}
    def kind(_kind), do: :error
  end

  defmodule ErrorPayload do
    @moduledoc "tsgolint error frame."
    use JSONCodec, strict: true

    defstruct [:error]
    @type t :: %__MODULE__{error: String.t()}
  end

  @type severity :: OXC.Lint.severity()
  @type diagnostic :: OXC.Lint.diagnostic()

  @type option ::
          {:type_aware, true}
          | {:rules, %{String.t() => OXC.Lint.severity() | {OXC.Lint.severity(), term()}}}
          | {:plugins, [OXC.Lint.plugin()]}
          | {:tsgolint, String.t()}
          | {:type_check, boolean()}
          | {:report_syntactic, boolean()}
          | {:report_semantic, boolean()}
          | {:fix, boolean()}
          | {:fix_suggestions, boolean()}
          | {:source_overrides, %{String.t() => String.t()}}
          | {:cwd, Path.t()}

  @doc "Run tsgolint on a list of files."
  @spec run([String.t()], [option()]) :: {:ok, [diagnostic()]} | {:error, [diagnostic()]}
  def run(files, opts \\ []) when is_list(files) do
    with {:ok, executable} <- find_executable(opts),
         {:ok, output} <- run_tsgolint(executable, files, opts),
         {:ok, findings} <- findings(output, opts) do
      {:ok, diagnostics(findings, opts)}
    else
      {:error, errors} -> {:error, OXC.Diagnostic.from_raw(errors, nil, nil)}
    end
  end

  defp findings(output, opts) when is_binary(output),
    do: parse_output(output, severity_by_rule(opts))

  defp findings(findings, _opts), do: {:ok, findings}

  # Load each reported file once, preferring the source tsgolint checked, and
  # convert its findings' byte ranges to positions.
  defp diagnostics(findings, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    overrides =
      Map.new(Keyword.get(opts, :source_overrides, %{}), fn {path, source} ->
        {Path.expand(path, cwd), source}
      end)

    findings
    |> Enum.chunk_by(& &1.file)
    |> Enum.flat_map(fn [%{file: file} | _] = chunk ->
      OXC.Diagnostic.from_raw(
        chunk,
        file,
        file && checked_source(Path.expand(file, cwd), overrides)
      )
    end)
  end

  defp checked_source(path, overrides) do
    case Map.fetch(overrides, path) do
      {:ok, source} ->
        source

      :error ->
        case File.read(path) do
          {:ok, source} -> source
          {:error, _reason} -> nil
        end
    end
  end

  @doc """
  Parse tsgolint headless output frames into raw findings, or the error messages it reported.

  `severities` maps tsgolint rule names to their configured `t:OXC.Lint.severity/0`.
  """
  def parse_output(output, severities \\ %{}) when is_binary(output) do
    parse_frames(output, severities, [], [])
  end

  defp find_executable(opts) do
    executable =
      Keyword.get(opts, :tsgolint) ||
        get_in(Application.get_env(:oxc, :tsgolint, []), [:executable]) ||
        System.find_executable("tsgolint")

    cond do
      is_binary(executable) and File.exists?(executable) -> {:ok, executable}
      is_binary(executable) and System.find_executable(executable) -> {:ok, executable}
      true -> {:error, ["tsgolint executable not found; pass tsgolint: \"/path/to/tsgolint\""]}
    end
  end

  defp run_tsgolint(executable, files, opts) do
    payload_path = write_payload!(build_payload(files, opts))
    stderr_path = OXC.Process.tmp_path("oxc-tsgolint-stderr")
    args = ["headless" | headless_flags(opts)]

    try do
      {output, status} =
        OXC.Process.run(executable, args,
          stdin_file: payload_path,
          stderr_file: stderr_path,
          cd: Keyword.get(opts, :cwd, File.cwd!())
        )

      stderr = OXC.Process.read_file(stderr_path)
      handle_tsgolint_result(output, stderr, status, severity_by_rule(opts))
    after
      File.rm(payload_path)
      File.rm(stderr_path)
    end
  rescue
    # Boundary around an external program: any failure to launch or talk to
    # tsgolint becomes an error result instead of crashing the caller.
    # reach:disable-next-line bare_rescue
    exception -> {:error, [Exception.message(exception)]}
  end

  defp write_payload!(payload) do
    path = OXC.Process.tmp_path("oxc-tsgolint-payload", ".json")
    File.write!(path, Jason.encode!(payload))
    path
  end

  defp handle_tsgolint_result(output, _stderr, 0, _severities), do: {:ok, output}

  defp handle_tsgolint_result(output, stderr, status, severities) do
    case {parse_output(output, severities), stderr} do
      {{:ok, []}, _stderr} ->
        {:error, [tsgolint_failure_message(stderr, status)]}

      {{:ok, diagnostics}, ""} ->
        {:ok, diagnostics}

      {{:ok, _diagnostics}, _stderr} ->
        {:error, [tsgolint_failure_message(stderr, status)]}

      {{:error, errors}, ""} ->
        {:error, errors}

      {{:error, errors}, _stderr} ->
        {:error, errors ++ [tsgolint_failure_message(stderr, status)]}
    end
  end

  defp tsgolint_failure_message("", status), do: "tsgolint exited with status #{status}"

  defp tsgolint_failure_message(stderr, status) do
    stderr = String.trim(stderr)

    if stderr == "" do
      "tsgolint exited with status #{status}"
    else
      "tsgolint exited with status #{status}: #{stderr}"
    end
  end

  defp build_payload(files, opts) do
    %Payload{
      configs: [%Config{file_paths: Enum.map(files, &Path.expand/1), rules: rules(opts)}],
      source_overrides: Keyword.get(opts, :source_overrides, %{}),
      report_syntactic:
        Keyword.get(opts, :type_check, false) or Keyword.get(opts, :report_syntactic, false),
      report_semantic:
        Keyword.get(opts, :type_check, false) or Keyword.get(opts, :report_semantic, false)
    }
  end

  defp rules(opts) do
    for {name, config} <- Keyword.get(opts, :rules, %{}), severity(config) != :allow do
      %Rule{name: tsgolint_rule_name(name), options: rule_options(config)}
    end
  end

  defp severity_by_rule(opts) do
    Map.new(Keyword.get(opts, :rules, %{}), fn {name, config} ->
      {tsgolint_rule_name(name), severity(config)}
    end)
  end

  defp severity({severity, _options}), do: severity
  defp severity(severity), do: severity

  defp rule_options({_severity, options}), do: options
  defp rule_options(_severity), do: nil

  defp tsgolint_rule_name("typescript/" <> name), do: name
  defp tsgolint_rule_name(name), do: name

  defp headless_flags(opts) do
    []
    |> maybe_flag(Keyword.get(opts, :fix, false), "-fix")
    |> maybe_flag(Keyword.get(opts, :fix_suggestions, false), "-fix-suggestions")
  end

  defp maybe_flag(args, true, flag), do: [flag | args]
  defp maybe_flag(args, _enabled, _flag), do: args

  defp parse_frames(<<>>, _severities, [], diagnostics), do: {:ok, Enum.reverse(diagnostics)}
  defp parse_frames(<<>>, _severities, errors, _diagnostics), do: {:error, Enum.reverse(errors)}

  defp parse_frames(
         <<length::little-32, type::unsigned-8, rest::binary>>,
         severities,
         errors,
         diagnostics
       )
       when byte_size(rest) >= length do
    <<payload::binary-size(^length), tail::binary>> = rest

    case decode_frame(type, payload, severities) do
      {:diagnostic, diagnostic} ->
        parse_frames(tail, severities, errors, [diagnostic | diagnostics])

      {:error, message} ->
        parse_frames(tail, severities, [message | errors], diagnostics)

      :ignore ->
        parse_frames(tail, severities, errors, diagnostics)
    end
  end

  defp parse_frames(_truncated, _severities, errors, diagnostics) do
    if errors == [] do
      {:ok, Enum.reverse(diagnostics)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp decode_frame(0, payload, _severities) do
    case ErrorPayload.decode(payload) do
      {:ok, %ErrorPayload{error: message}} -> {:error, message}
      {:error, error} -> {:error, "invalid tsgolint error frame: #{Exception.message(error)}"}
    end
  end

  defp decode_frame(1, payload, severities) do
    case DiagnosticPayload.decode(payload) do
      {:ok, diagnostic} -> {:diagnostic, finding(diagnostic, severities)}
      {:error, error} -> {:error, "invalid tsgolint diagnostic: #{Exception.message(error)}"}
    end
  end

  defp decode_frame(_type, _payload, _severities), do: :ignore

  # A raw finding in the shape `OXC.Diagnostic.from_raw/3` accepts, plus the reported file.
  # Rule findings take the configured severity; internal TypeScript diagnostics are errors.
  defp finding(%DiagnosticPayload{kind: :rule, rule: rule} = diagnostic, severities) do
    severity = if Map.get(severities, rule) == :deny, do: :error, else: :warning
    finding(diagnostic, "typescript/" <> rule, severity)
  end

  defp finding(%DiagnosticPayload{kind: :internal, message: message} = diagnostic, _severities) do
    finding(diagnostic, "typescript/" <> message.id, :error)
  end

  defp finding(%DiagnosticPayload{message: message} = diagnostic, rule, severity) do
    %{
      file: diagnostic.file_path,
      rule: rule,
      severity: severity,
      message: message.description,
      help: message.help,
      labels: primary_label(diagnostic.range) ++ Enum.map(diagnostic.labeled_ranges, &label/1),
      fixes: Enum.map(diagnostic.fixes, &fix/1),
      suggestions:
        Enum.map(diagnostic.suggestions, fn %Suggestion{message: message, fixes: fixes} ->
          %{message: message.description, fixes: Enum.map(fixes, &fix/1)}
        end)
    }
  end

  defp primary_label(nil), do: []
  defp primary_label(%Range{pos: start, end: stop}), do: [{start, stop, nil}]

  defp label(%LabeledRange{label: label, range: %Range{pos: start, end: stop}}),
    do: {start, stop, label}

  defp fix(%Fix{text: text, range: %Range{pos: start, end: stop}}), do: {start, stop, text}
end
