use std::path::PathBuf;

use oxc_allocator::Allocator;
use oxc_codegen::{Codegen, CodegenOptions, CodegenReturn, CommentOptions};
use oxc_isolated_declarations::{IsolatedDeclarations, IsolatedDeclarationsOptions};
use oxc_parser::Parser;
use oxc_span::SourceType;
use rustler::{Env, NifResult, Term};

use crate::error::diagnostics;
use crate::options::DeclarationsInput;
use crate::parse::{binary_to_str, parser_options, source_from_term, TransformOutput};

/// Emit the `.d.ts` of a TypeScript source without a type checker, as
/// `tsc --isolatedDeclarations` would: exported declarations need explicit
/// types, and the emitter reports those it cannot infer.
pub fn declarations_source(
    source: &str,
    filename: &str,
    opts: &DeclarationsInput,
) -> TransformOutput {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();

    let ret = Parser::new(&allocator, source, source_type)
        .with_options(parser_options())
        .parse();

    if !ret.errors.is_empty() {
        return TransformOutput::Error(diagnostics(&ret.errors));
    }

    let result = IsolatedDeclarations::new(
        &allocator,
        IsolatedDeclarationsOptions {
            strip_internal: opts.strip_internal,
        },
    )
    .build(&ret.program);

    if !result.errors.is_empty() {
        return TransformOutput::Error(diagnostics(&result.errors));
    }

    // Declarations keep their JSDoc, which documents the API, and nothing else.
    let options = CodegenOptions {
        comments: CommentOptions {
            jsdoc: true,
            ..CommentOptions::disabled()
        },
        source_map_path: opts.sourcemap.then(|| PathBuf::from(filename)),
        ..CodegenOptions::default()
    };

    let CodegenReturn { code, map, .. } =
        Codegen::new().with_options(options).build(&result.program);

    match map {
        Some(map) if opts.sourcemap => TransformOutput::CodeWithMap {
            code,
            sourcemap: map.to_json_string(),
        },
        _ => TransformOutput::Code(code),
    }
}

pub fn isolated_declarations_impl<'a>(
    env: Env<'a>,
    source_term: Term<'a>,
    filename: &str,
    opts_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let opts = DeclarationsInput::from_term(opts_term);
    Ok(declarations_source(source, filename, &opts).to_term(env))
}
