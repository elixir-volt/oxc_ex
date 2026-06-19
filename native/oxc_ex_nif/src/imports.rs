use oxc_allocator::Allocator;
use oxc_ast::ast::{Argument, Expression, ImportOrExportKind};
use oxc_ast_visit::walk;
use oxc_ast_visit::Visit;
use oxc_parser::Parser;
use oxc_span::SourceType;
use rustler::{Atom, Encoder, Env, NifResult, Term};
use rustler_match_spec::{MatchEvent, Selector, ValueRef};

use crate::atoms;
use crate::error::{error_to_term, format_errors};
use crate::parse::{binary_to_str, source_from_term};

struct ImportInfo {
    specifier: String,
    r#type: rustler::Atom,
    kind: rustler::Atom,
    start: u32,
    r#end: u32,
}

struct AssetUrlInfo {
    specifier: String,
    start: u32,
    r#end: u32,
}

struct ImportCollector {
    imports: Vec<ImportInfo>,
    asset_urls: Vec<AssetUrlInfo>,
}

impl<'a> MatchEvent<'a> for &'a AssetUrlInfo {
    fn tag(&self) -> Atom {
        atoms::asset_url()
    }

    fn arity(&self) -> usize {
        4
    }

    fn positional_field(&self, index: usize) -> Option<ValueRef<'a>> {
        match index {
            1 => Some(ValueRef::Str(self.specifier.as_str())),
            2 => Some(ValueRef::U64(self.start.into())),
            3 => Some(ValueRef::U64(self.r#end.into())),
            _ => None,
        }
    }

    fn field(&self, name: Atom) -> Option<ValueRef<'a>> {
        if name == atoms::specifier() {
            Some(ValueRef::Str(self.specifier.as_str()))
        } else if name == atoms::start() {
            Some(ValueRef::U64(self.start.into()))
        } else if name == atoms::r#end() {
            Some(ValueRef::U64(self.r#end.into()))
        } else {
            None
        }
    }
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

    fn visit_new_expression(&mut self, expr: &oxc_ast::ast::NewExpression<'a>) {
        if is_url_constructor(&expr.callee) && expr.arguments.len() >= 2 {
            if let (Some(source), Some(base)) = (expr.arguments.first(), expr.arguments.get(1)) {
                if let (Argument::StringLiteral(lit), true) =
                    (source, is_import_meta_url_argument(base))
                {
                    self.asset_urls.push(AssetUrlInfo {
                        specifier: lit.value.to_string(),
                        start: lit.span.start,
                        r#end: lit.span.end,
                    });
                }
            }
        }

        walk::walk_new_expression(self, expr);
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
        asset_urls: Vec::new(),
    };
    collector.visit_program(&ret.program);

    let mut out = Vec::new();

    for import in &collector.imports {
        selector.run_event(env, &import, &mut out)?;
    }

    for asset_url in &collector.asset_urls {
        selector.run_event(env, &asset_url, &mut out)?;
    }

    Ok((atoms::ok(), out).encode(env))
}

fn is_url_constructor(expr: &Expression<'_>) -> bool {
    matches!(expr, Expression::Identifier(identifier) if identifier.name == "URL")
}

fn is_import_meta_url_argument(argument: &Argument<'_>) -> bool {
    matches!(argument, Argument::StaticMemberExpression(member) if is_import_meta_url(member))
}

fn is_import_meta_url(member: &oxc_ast::ast::StaticMemberExpression<'_>) -> bool {
    member.property.name == "url"
        && matches!(
            &member.object,
            Expression::MetaProperty(meta) if meta.meta.name == "import" && meta.property.name == "meta"
        )
}
