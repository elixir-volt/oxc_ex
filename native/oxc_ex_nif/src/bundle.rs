use std::collections::BTreeSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

use oxc95::minifier::{
    CompressOptions as RolldownCompressOptions, MangleOptions as RolldownMangleOptions,
    MangleOptionsKeepNames as RolldownMangleOptionsKeepNames,
};
use oxc_allocator::Allocator;
use oxc_ast::ast::{ImportOrExportKind, Statement};
use oxc_parser::{ParseOptions, Parser};
use oxc_span::SourceType;
use rolldown::{
    AddonOutputOption, Bundler, BundlerOptions, BundlerTransformOptions, Either as RolldownEither,
    InputItem, IsExternal, JsxOptions as RolldownJsxOptions, OutputFormat, RawMinifyOptions,
    RawMinifyOptionsDetailed, ResolveOptions as RolldownResolveOptions, SourceMapType,
    TreeshakeOptions,
};
use rolldown_common::Output;
use rustler::{Encoder, Env, NifResult, SerdeTerm, Term};
use serde::Serialize;
use serde_json::Value;
use tempfile::TempDir;
use tokio::runtime::Builder as RuntimeBuilder;

use crate::atoms;
use crate::error::{error_to_term, format_errors};
use crate::options::{decode_options, BundleOptions};

#[derive(Serialize)]
struct CodeWithSourcemap {
    code: String,
    sourcemap: String,
}

fn normalize_virtual_path(path: &str) -> Result<PathBuf, String> {
    let normalized = path.replace('\\', "/");
    let mut result = PathBuf::new();

    for component in Path::new(&normalized).components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                result.pop();
            }
            Component::Normal(part) => result.push(part),
            Component::RootDir | Component::Prefix(_) => {}
        }
    }

    if result.as_os_str().is_empty() {
        return Err(format!("Invalid virtual filename: {path:?}"));
    }

    Ok(result)
}

fn is_bare_specifier(specifier: &str) -> bool {
    !specifier.starts_with('.') && !specifier.starts_with('/')
}

fn collect_external_specifiers(files: &[(String, String)]) -> Result<Vec<String>, Vec<String>> {
    let mut specifiers = BTreeSet::new();

    for (filename, source) in files {
        let allocator = Allocator::default();
        let source_type = SourceType::from_path(filename).unwrap_or_default();
        let ret = Parser::new(&allocator, source, source_type)
            .with_options(ParseOptions::default())
            .parse();

        if !ret.errors.is_empty() {
            return Err(format_errors(&ret.errors));
        }

        for statement in ret.program.body.iter() {
            match statement {
                Statement::ImportDeclaration(decl)
                    if decl.import_kind != ImportOrExportKind::Type
                        && is_bare_specifier(decl.source.value.as_str()) =>
                {
                    specifiers.insert(decl.source.value.to_string());
                }
                Statement::ExportAllDeclaration(decl)
                    if decl.export_kind != ImportOrExportKind::Type
                        && is_bare_specifier(decl.source.value.as_str()) =>
                {
                    specifiers.insert(decl.source.value.to_string());
                }
                Statement::ExportNamedDeclaration(decl) => {
                    if decl.export_kind != ImportOrExportKind::Type {
                        if let Some(source) = &decl.source {
                            if is_bare_specifier(source.value.as_str()) {
                                specifiers.insert(source.value.to_string());
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }

    Ok(specifiers.into_iter().collect())
}

fn write_virtual_project(
    tempdir: &TempDir,
    files: &[(String, String)],
) -> Result<Vec<String>, Vec<String>> {
    let mut written = BTreeSet::new();

    for (filename, source) in files {
        let relative_path = match normalize_virtual_path(filename) {
            Ok(path) => path,
            Err(message) => return Err(vec![message]),
        };
        let import_path = relative_path.to_string_lossy().replace('\\', "/");

        if !written.insert(import_path.clone()) {
            return Err(vec![format!(
                "Duplicate module path after normalization: {filename:?}"
            )]);
        }

        let full_path = tempdir.path().join(&relative_path);
        if let Some(parent) = full_path.parent() {
            if let Err(error) = fs::create_dir_all(parent) {
                return Err(vec![format!(
                    "Failed to create directory for {filename:?}: {error}"
                )]);
            }
        }

        if let Err(error) = fs::write(&full_path, source) {
            return Err(vec![format!("Failed to write {filename:?}: {error}")]);
        }
    }

    Ok(written.into_iter().collect())
}

fn build_rolldown_resolve_options() -> RolldownResolveOptions {
    RolldownResolveOptions {
        extensions: Some(vec![
            ".tsx".to_string(),
            ".ts".to_string(),
            ".jsx".to_string(),
            ".js".to_string(),
            ".json".to_string(),
        ]),
        extension_alias: Some(vec![
            (
                ".js".to_string(),
                vec![
                    ".ts".to_string(),
                    ".tsx".to_string(),
                    ".js".to_string(),
                    ".jsx".to_string(),
                ],
            ),
            (
                ".jsx".to_string(),
                vec![
                    ".tsx".to_string(),
                    ".ts".to_string(),
                    ".jsx".to_string(),
                    ".js".to_string(),
                ],
            ),
        ]),
        ..RolldownResolveOptions::default()
    }
}

fn build_rolldown_transform_options(opts: &BundleOptions) -> BundlerTransformOptions {
    let jsx = (opts.jsx_runtime != "automatic"
        || !opts.jsx_factory.is_empty()
        || !opts.jsx_fragment.is_empty()
        || !opts.import_source.is_empty())
    .then(|| {
        RolldownEither::Right(RolldownJsxOptions {
            runtime: Some(opts.jsx_runtime.clone()),
            import_source: (!opts.import_source.is_empty()).then(|| opts.import_source.clone()),
            pragma: (!opts.jsx_factory.is_empty()).then(|| opts.jsx_factory.clone()),
            pragma_frag: (!opts.jsx_fragment.is_empty()).then(|| opts.jsx_fragment.clone()),
            ..RolldownJsxOptions::default()
        })
    });

    BundlerTransformOptions {
        jsx,
        target: (!opts.target.is_empty()).then(|| RolldownEither::Left(opts.target.clone())),
        ..BundlerTransformOptions::default()
    }
}

fn build_minify_options(drop_console: bool) -> RawMinifyOptions {
    if !drop_console {
        return RawMinifyOptions::Bool(true);
    }

    let compress = RolldownCompressOptions {
        drop_console: true,
        ..RolldownCompressOptions::smallest()
    };
    let mangle = RolldownMangleOptions {
        top_level: false,
        keep_names: RolldownMangleOptionsKeepNames::all_false(),
        debug: false,
    };

    RawMinifyOptions::Object(RawMinifyOptionsDetailed {
        options: oxc95::minifier::MinifierOptions {
            mangle: Some(mangle),
            compress: Some(compress),
        },
        default_target: true,
        remove_whitespace: true,
    })
}

fn relativize_sourcemap_sources(sourcemap_json: String, cwd: &Path) -> Result<String, Vec<String>> {
    let mut json = serde_json::from_str::<Value>(&sourcemap_json)
        .map_err(|error| vec![format!("Failed to parse Rolldown source map: {error}")])?;

    if let Some(sources) = json.get_mut("sources").and_then(Value::as_array_mut) {
        for source in sources {
            if let Some(path) = source.as_str() {
                let source_path = Path::new(path);
                if let Ok(relative) = source_path.strip_prefix(cwd) {
                    *source = Value::String(relative.to_string_lossy().replace('\\', "/"));
                }
            }
        }
    }

    serde_json::to_string(&json)
        .map_err(|error| vec![format!("Failed to serialize Rolldown source map: {error}")])
}

fn inject_preamble(code: &str, preamble: &str) -> String {
    if let Some(pos) = code.find("(function") {
        if let Some(brace_offset) = code[pos..].find('{') {
            let insert_at = pos + brace_offset + 1;
            let mut result = String::with_capacity(code.len() + preamble.len() + 2);
            result.push_str(&code[..insert_at]);
            result.push('\n');
            result.push_str(preamble);
            result.push_str(&code[insert_at..]);
            return result;
        }
    }
    format!("{preamble}\n{code}")
}

fn build_bundle_options(
    cwd: &Path,
    entry_name: String,
    opts: &BundleOptions,
    external_specifiers: Vec<String>,
) -> BundlerOptions {
    BundlerOptions {
        input: Some(vec![InputItem {
            name: Some("bundle".to_string()),
            import: entry_name,
        }]),
        cwd: Some(cwd.to_path_buf()),
        external: (!external_specifiers.is_empty()).then(|| IsExternal::from(external_specifiers)),
        file: Some("bundle.js".to_string()),
        format: Some(match opts.format.as_str() {
            "esm" => OutputFormat::Esm,
            "cjs" => OutputFormat::Cjs,
            _ => OutputFormat::Iife,
        }),
        sourcemap: opts.sourcemap.then_some(SourceMapType::Hidden),
        banner: opts
            .banner
            .clone()
            .map(|s| AddonOutputOption::String(Some(s))),
        footer: opts
            .footer
            .clone()
            .map(|s| AddonOutputOption::String(Some(s))),
        define: (!opts.define.is_empty()).then(|| {
            opts.define
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect()
        }),
        resolve: Some(build_rolldown_resolve_options()),
        transform: Some(build_rolldown_transform_options(opts)),
        treeshake: TreeshakeOptions::Boolean(opts.treeshake),
        minify: opts.minify.then(|| build_minify_options(opts.drop_console)),
        ..BundlerOptions::default()
    }
}

fn bundle_with_rolldown(
    files: Vec<(String, String)>,
    opts: &BundleOptions,
) -> Result<(String, Option<String>), Vec<String>> {
    if files.is_empty() {
        return Err(vec!["bundle/2 requires at least one file".to_string()]);
    }
    if opts.entry.is_empty() {
        return Err(vec!["bundle/2 requires an :entry option".to_string()]);
    }

    let entry_name = normalize_virtual_path(&opts.entry)
        .map(|path| path.to_string_lossy().replace('\\', "/"))
        .map_err(|message| vec![message])?;
    let external_specifiers = collect_external_specifiers(&files)?;
    let tempdir = TempDir::new()
        .map_err(|error| vec![format!("Failed to create temp directory: {error}")])?;
    let cwd = tempdir
        .path()
        .canonicalize()
        .unwrap_or_else(|_| tempdir.path().to_path_buf());
    let written_paths = write_virtual_project(&tempdir, &files)?;
    if !written_paths.iter().any(|path| path == &entry_name) {
        return Err(vec![format!(
            "bundle entry {entry_name:?} was not found in files"
        )]);
    }
    let options = build_bundle_options(&cwd, entry_name, opts, external_specifiers);
    let runtime = RuntimeBuilder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| vec![format!("Failed to initialize Tokio runtime: {error}")])?;

    let mut bundler = Bundler::new(options)
        .map_err(|errors| errors.iter().map(ToString::to_string).collect::<Vec<_>>())?;

    let output = runtime
        .block_on(bundler.generate())
        .map_err(|errors| errors.iter().map(ToString::to_string).collect::<Vec<_>>())?;

    let _ = runtime.block_on(bundler.close());

    let chunk = output
        .assets
        .into_iter()
        .find_map(|asset| match asset {
            Output::Chunk(chunk) if chunk.filename == "bundle.js" => Some(chunk),
            _ => None,
        })
        .ok_or_else(|| vec!["Rolldown did not produce a JavaScript bundle".to_string()])?;

    let mut code = chunk.code.clone();

    if let Some(preamble) = &opts.preamble {
        if !preamble.is_empty() {
            code = inject_preamble(&code, preamble);
        }
    }

    let sourcemap = if opts.sourcemap {
        let sourcemap_json = chunk
            .map
            .as_ref()
            .map(oxc_sourcemap::SourceMap::to_json_string)
            .ok_or_else(|| vec!["Rolldown did not produce a source map".to_string()])?;
        Some(relativize_sourcemap_sources(sourcemap_json, &cwd)?)
    } else {
        None
    };

    Ok((code, sourcemap))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn bundle<'a>(
    env: Env<'a>,
    files: Vec<(String, String)>,
    opts_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let opts = decode_options::<BundleOptions>(opts_term);

    match bundle_with_rolldown(files, &opts) {
        Ok((code, Some(sourcemap))) => Ok((
            atoms::ok(),
            SerdeTerm(CodeWithSourcemap { code, sourcemap }),
        )
            .encode(env)),
        Ok((code, None)) => Ok((atoms::ok(), SerdeTerm(code)).encode(env)),
        Err(errors) => error_to_term(env, &errors),
    }
}
