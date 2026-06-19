use oxc_allocator::Allocator;
use oxc_ast::ast::{Expression, ImportOrExportKind, Statement};
use oxc_ast_visit::walk;
use oxc_ast_visit::Visit;
use oxc_parser::Parser;
use oxc_span::SourceType;
use rustler::{Atom, Encoder, Env, NifMap, NifResult, Term};
use rustler_match_spec::{MatchEvent, Selector, ValueRef};

use crate::atoms;
use crate::error::{error_to_term, format_errors};
use crate::parse::{binary_to_str, source_from_term};

#[derive(NifMap)]
struct ImportInfo {
    specifier: String,
    r#type: rustler::Atom,
    kind: rustler::Atom,
    start: u32,
    r#end: u32,
}

struct ImportCollector {
    imports: Vec<ImportInfo>,
}

impl<'a> MatchEvent<'a> for &'a ImportInfo {
    fn tag(&self) -> Atom {
        atoms::import_source()
    }

    fn arity(&self) -> usize {
        6
    }

    fn positional_field(&self, index: usize) -> Option<ValueRef<'a>> {
        match index {
            1 => Some(ValueRef::Str(self.specifier.as_str())),
            2 => Some(ValueRef::Atom(self.r#type)),
            3 => Some(ValueRef::Atom(self.kind)),
            4 => Some(ValueRef::U64(self.start.into())),
            5 => Some(ValueRef::U64(self.r#end.into())),
            _ => None,
        }
    }

    fn field(&self, name: Atom) -> Option<ValueRef<'a>> {
        if name == atoms::specifier() {
            Some(ValueRef::Str(self.specifier.as_str()))
        } else if name == atoms::r#type() {
            Some(ValueRef::Atom(self.r#type))
        } else if name == atoms::kind() {
            Some(ValueRef::Atom(self.kind))
        } else if name == atoms::start() {
            Some(ValueRef::U64(self.start.into()))
        } else if name == atoms::r#end() {
            Some(ValueRef::U64(self.r#end.into()))
        } else {
            None
        }
    }
}

impl<'a> Visit<'a> for ImportCollector {
    fn visit_import_declaration(&mut self, decl: &oxc_ast::ast::ImportDeclaration<'a>) {
        if decl.import_kind != ImportOrExportKind::Type {
            self.imports.push(ImportInfo {
                specifier: decl.source.value.to_string(),
                r#type: atoms::atom_static(),
                kind: atoms::import(),
                start: decl.source.span.start,
                r#end: decl.source.span.end,
            });
        }
    }

    fn visit_export_named_declaration(&mut self, decl: &oxc_ast::ast::ExportNamedDeclaration<'a>) {
        if decl.export_kind != ImportOrExportKind::Type {
            if let Some(source) = &decl.source {
                self.imports.push(ImportInfo {
                    specifier: source.value.to_string(),
                    r#type: atoms::atom_static(),
                    kind: atoms::export(),
                    start: source.span.start,
                    r#end: source.span.end,
                });
            }
        }
        walk::walk_export_named_declaration(self, decl);
    }

    fn visit_export_all_declaration(&mut self, decl: &oxc_ast::ast::ExportAllDeclaration<'a>) {
        if decl.export_kind != ImportOrExportKind::Type {
            self.imports.push(ImportInfo {
                specifier: decl.source.value.to_string(),
                r#type: atoms::atom_static(),
                kind: atoms::export_all(),
                start: decl.source.span.start,
                r#end: decl.source.span.end,
            });
        }
    }

    fn visit_import_expression(&mut self, expr: &oxc_ast::ast::ImportExpression<'a>) {
        if let Expression::StringLiteral(lit) = &expr.source {
            self.imports.push(ImportInfo {
                specifier: lit.value.to_string(),
                r#type: atoms::dynamic(),
                kind: atoms::import(),
                start: lit.span.start,
                r#end: lit.span.end,
            });
        }
        walk::walk_import_expression(self, expr);
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn imports<'a>(env: Env<'a>, source_term: Term<'a>, filename: &str) -> NifResult<Term<'a>> {
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let ret = Parser::new(&allocator, source, source_type).parse();

    if !ret.errors.is_empty() {
        return error_to_term(env, &format_errors(&ret.errors));
    }

    let specifiers: Vec<String> = ret
        .program
        .body
        .iter()
        .filter_map(|stmt| match stmt {
            Statement::ImportDeclaration(decl) if decl.import_kind != ImportOrExportKind::Type => {
                Some(decl.source.value.to_string())
            }
            _ => None,
        })
        .collect();

    Ok((atoms::ok(), rustler::SerdeTerm(specifiers)).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn collect_imports<'a>(
    env: Env<'a>,
    source_term: Term<'a>,
    filename: &str,
) -> NifResult<Term<'a>> {
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let ret = Parser::new(&allocator, source, source_type).parse();

    if !ret.errors.is_empty() {
        return error_to_term(env, &format_errors(&ret.errors));
    }

    let mut collector = ImportCollector {
        imports: Vec::new(),
    };
    collector.visit_program(&ret.program);

    Ok((atoms::ok(), collector.imports).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn select<'a>(
    env: Env<'a>,
    source_term: Term<'a>,
    filename: &str,
    spec: Term<'a>,
) -> NifResult<Term<'a>> {
    let selector = Selector::from_term(spec)?;
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let ret = Parser::new(&allocator, source, source_type).parse();

    if !ret.errors.is_empty() {
        return error_to_term(env, &format_errors(&ret.errors));
    }

    let mut collector = ImportCollector {
        imports: Vec::new(),
    };
    collector.visit_program(&ret.program);

    let mut out = Vec::new();

    for import in &collector.imports {
        selector.run_event(env, &import, &mut out)?;
    }

    Ok((atoms::ok(), out).encode(env))
}
