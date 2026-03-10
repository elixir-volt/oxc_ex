use oxc_allocator::Allocator;
use oxc_parser::{ParseOptions, Parser};
use oxc_span::SourceType;
use rustler::{Encoder, Env, NifResult, Term};
use serde_json::Value;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        message,
        span,
    }
}

fn json_to_term<'a>(env: Env<'a>, value: &Value) -> Term<'a> {
    match value {
        Value::Null => rustler::types::atom::nil().encode(env),
        Value::Bool(b) => b.encode(env),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.encode(env)
            } else if let Some(f) = n.as_f64() {
                f.encode(env)
            } else {
                rustler::types::atom::nil().encode(env)
            }
        }
        Value::String(s) => s.as_str().encode(env),
        Value::Array(arr) => {
            let terms: Vec<Term<'a>> = arr.iter().map(|v| json_to_term(env, v)).collect();
            terms.encode(env)
        }
        Value::Object(map) => {
            let keys: Vec<Term<'a>> = map
                .keys()
                .map(|k| {
                    rustler::types::atom::Atom::from_str(env, k)
                        .unwrap()
                        .encode(env)
                })
                .collect();
            let vals: Vec<Term<'a>> = map.values().map(|v| json_to_term(env, v)).collect();
            Term::map_from_arrays(env, &keys, &vals).unwrap()
        }
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse<'a>(env: Env<'a>, source: &str, filename: &str) -> NifResult<Term<'a>> {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let ret = Parser::new(&allocator, source, source_type)
        .with_options(ParseOptions {
            parse_regular_expression: true,
            ..ParseOptions::default()
        })
        .parse();

    if !ret.errors.is_empty() {
        let errors: Vec<Term<'a>> = ret
            .errors
            .iter()
            .map(|e| {
                let msg = e.to_string();
                Term::map_from_arrays(env, &[atoms::message().encode(env)], &[msg.encode(env)])
                    .unwrap()
            })
            .collect();
        return Ok((atoms::error(), errors).encode(env));
    }

    let json_str = ret.program.to_estree_ts_json(false);
    let json: Value = serde_json::from_str(&json_str).unwrap();
    let term = json_to_term(env, &json);

    Ok((atoms::ok(), term).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn valid(source: &str, filename: &str) -> bool {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let ret = Parser::new(&allocator, source, source_type).parse();
    ret.errors.is_empty()
}

rustler::init!("Elixir.OxcEx.Native");
