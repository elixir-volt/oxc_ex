mod bundle;
mod codegen;
mod error;
mod imports;
mod options;
mod parse;
mod transform_many;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        atom_static = "static",
        dynamic,
        import,
        export,
        export_all,
        entry,
        cwd,
        format,
        exports,
        minify,
        treeshake,
        banner,
        footer,
        preamble,
        define,
        module_types,
        external,
        preserve_entry_signatures,
        conditions,
        main_fields,
        modules,
        sourcemap,
        drop_console,
        jsx,
        jsx_factory,
        jsx_fragment,
        import_source,
        target,
        mangle,
        entries,
        files,
        outdir,
        entry_file_names,
        chunk_file_names,
        asset_file_names,
        name,
        source,
        outputs,
        warnings,
        specifier,
        kind,
        start,
        r#end = "end",
        r#type = "type",
        file_name,
        path,
        code,
        asset,
        asset_url,
        chunk,
        dynamic_imports,
    }
}

rustler::init!("Elixir.OXC.Native");
