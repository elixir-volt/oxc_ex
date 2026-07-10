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

type_key = Rust.path([:a, "r#type"]) <> "()"

rust "native/oxc_ex_nif/src/generated_term_helpers.rs" do
  Rustler.term_helpers(
    type_key: type_key,
    include: [:get, :is_nil, :opt, :str_val, :bool_val, :f64_val, :list_val, :type_atom, :type_eq, :type_str]
  )
end

rust "native/oxc_ex_nif/src/generated_option_helpers.rs" do
  Rustler.term_helpers(
    include: [:get, :is_nil, :get_bool, :get_string, :get_string_list, :get_term_list]
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
