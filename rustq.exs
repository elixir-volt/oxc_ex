use RustQ.Config

alias RustQ.{Rust, Rustler}

rust "native/oxc_ex_nif/src/generated_atoms.rs" do
  Rustler.atoms([
    :ok,
    :error,
    {:atom_static, "static"},
    :dynamic,
    :import,
    :export,
    :export_all,
    :entry,
    :cwd,
    :format,
    :exports,
    :minify,
    :treeshake,
    :banner,
    :footer,
    :preamble,
    :define,
    :module_types,
    :external,
    :preserve_entry_signatures,
    :conditions,
    :main_fields,
    :modules,
    :sourcemap,
    :drop_console,
    :jsx,
    :jsx_factory,
    :jsx_fragment,
    :import_source,
    :target,
    :mangle,
    :entries,
    :files,
    :outdir,
    :entry_file_names,
    :chunk_file_names,
    :asset_file_names,
    :name,
    :source,
    :outputs,
    :warnings,
    :specifier,
    :kind,
    :start,
    {"r#end", "end"},
    {"r#type", "type"},
    :file_name,
    :path,
    :patterns,
    :code,
    :asset,
    :asset_url,
    :worker,
    :shared_worker,
    :glob_import,
    :import_meta_env,
    :dynamic_import_template,
    :require_call,
    :template_start,
    :template_end,
    :pattern,
    :chunk,
    :dynamic_imports
  ])
end

rust "native/oxc_lint_nif/src/generated_atoms.rs" do
  Rustler.atoms([:ok, :error, :warn, :deny, :allow])
end

rust "native/oxc_fmt_nif/src/generated_atoms.rs" do
  Rustler.atoms([
    :ok,
    :error,
    :print_width,
    :tab_width,
    :use_tabs,
    :semi,
    :single_quote,
    :jsx_single_quote,
    :trailing_comma,
    :bracket_spacing,
    :bracket_same_line,
    :arrow_parens,
    :end_of_line,
    :quote_props,
    :single_attribute_per_line,
    :object_wrap,
    :experimental_operator_position,
    :experimental_ternaries,
    :embedded_language_formatting,
    :sort_imports,
    :sort_tailwindcss,
    :ignore_case,
    :sort_side_effects,
    :order,
    :newlines_between,
    :partition_by_newline,
    :partition_by_comment,
    :internal_pattern,
    :config,
    :stylesheet,
    :functions,
    :attributes,
    :preserve_whitespace,
    :preserve_duplicates
  ])
end

rust "native/oxc_fmt_nif/src/generated_option_helpers.rs" do
  Rustler.term_helpers(include: [:get, :get_bool, :get_i64, :get_string, :get_string_list, :get_map])
end

type_key = Rust.path([:a, "r#type"]) <> "()"

rust "native/oxc_ex_nif/src/generated_term_helpers.rs" do
  Rustler.term_helpers(
    type_key: type_key,
    include: [:get, :is_nil, :opt, :str_val, :bool_val, :f64_val, :list_val, :type_atom, :type_eq, :type_str]
  )
end

rust "native/oxc_ex_nif/src/generated_option_helpers.rs" do
  Rustler.term_helpers(
    include: [
      :get,
      :is_nil,
      :get_bool,
      :get_string,
      :get_optional_string,
      :get_string_list,
      :get_term_list
    ]
  )
end

rust "native/oxc_ex_nif/src/generated_ast_decoders.rs" do
  Rustler.term_decoder(:ProgramInput,
    fields: [
      body: [type: {:vec, "Term<'a>"}, key: "a::body()", required: true]
    ]
  )

  Rustler.term_decoder(:IfStatementInput,
    result: "R",
    fields: [
      test: [type: "Term<'a>", key: "a::test()", required: true],
      consequent: [type: "Term<'a>", key: "a::consequent()", required: true],
      alternate: [type: {:option, "Term<'a>"}, key: "a::alternate()"]
    ]
  )
end

fmt_source = "native/oxc_fmt_nif/src/lib.rs"
fmt_nifs = [format: [lifetime: :a]]

rust :fmt_nifs, "native/oxc_fmt_nif/src/generated_nifs.rs" do
  Rustler.nif_exports_from_source(fmt_source, fmt_nifs, schedule: :dirty_cpu)
end

generate :fmt_native_stubs, "lib/oxc/format/native/generated_stubs.ex" do
  build(fn ->
    Rustler.nif_stubs_from_source(fmt_source, fmt_nifs, OXC.Format.Native.GeneratedStubs)
  end)
end

lint_source = "native/oxc_lint_nif/src/lib.rs"
lint_nifs = [lint: [lifetime: :a]]

rust :lint_nifs, "native/oxc_lint_nif/src/generated_nifs.rs" do
  Rustler.nif_exports_from_source(lint_source, lint_nifs, schedule: :dirty_cpu)
end

generate :lint_native_stubs, "lib/oxc/lint/native/generated_stubs.ex" do
  build(fn ->
    Rustler.nif_stubs_from_source(lint_source, lint_nifs, OXC.Lint.Native.GeneratedStubs)
  end)
end

native_nif_groups = [
  {"native/oxc_ex_nif/src/parse.rs",
   [parse: [lifetime: :a], valid: [], transform: [lifetime: :a], minify: [lifetime: :a]]},
  {"native/oxc_ex_nif/src/bundle.rs",
   [bundle: [lifetime: :a], bundle_entry: [lifetime: :a], bundle_run: [lifetime: :a]]},
  {"native/oxc_ex_nif/src/imports.rs", [select: [lifetime: :a]]},
  {"native/oxc_ex_nif/src/transform_many.rs", [transform_many: [lifetime: :a]]},
  {"native/oxc_ex_nif/src/codegen.rs", [codegen: [lifetime: :a]]}
]

native_nif_functions =
  Enum.flat_map(native_nif_groups, fn {source, nifs} ->
    metadata = source |> RustQ.Syn.parse_file!() |> RustQ.Syn.functions()

    Enum.map(nifs, fn {name, _opts} ->
      implementation = "#{name}_impl"
      function = Enum.find(metadata, &(&1.name == implementation))

      function || raise ArgumentError, "NIF implementation #{implementation} not found in #{source}"
      {name, function}
    end)
  end)

rust :native_nifs, "native/oxc_ex_nif/src/generated_nifs.rs" do
  Enum.flat_map(native_nif_groups, fn {source, nifs} ->
    Rustler.nif_exports_from_source(source, nifs, schedule: :dirty_cpu)
  end)
end

generate :native_stubs, "lib/oxc/native/generated_stubs.ex" do
  content(Rustler.nif_stubs_from_functions(native_nif_functions, OXC.Native.GeneratedStubs))
end
