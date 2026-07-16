use oxc_allocator::{Allocator, Vec as OxcVec};
use oxc_ast::ast::{ArrayExpressionElement, Expression, ObjectPropertyKind, Program, Statement};
use oxc_ast_visit::{walk_mut, VisitMut};
use oxc_codegen::Codegen;
use oxc_parser::Parser;
use oxc_span::SourceType;
use rustler::{Encoder, Env, NifResult, Term};

use crate::atoms;
use crate::error::{error_to_term, format_errors};
use crate::parse::{binary_to_str, parser_options, source_from_term};

struct SpliceVisitor<'a> {
    allocator: &'a Allocator,
    source_type: SourceType,
    placeholder: String,
    replacements: Vec<&'a str>,
    errors: Vec<String>,
}

impl<'a> SpliceVisitor<'a> {
    fn parse_program(&mut self, source: &'a str) -> Option<Program<'a>> {
        let parsed = Parser::new(self.allocator, source, self.source_type)
            .with_options(parser_options())
            .parse();

        if parsed.errors.is_empty() {
            Some(parsed.program)
        } else {
            self.errors.extend(format_errors(&parsed.errors));
            None
        }
    }

    fn statement_replacements(&mut self) -> Option<OxcVec<'a, Statement<'a>>> {
        let mut statements = OxcVec::new_in(self.allocator);

        for source in self.replacements.clone() {
            // A leading empty statement prevents a string literal replacement from
            // becoming a Program directive, matching the ESTree splice representation.
            let prefixed = format!(";{source}");
            let prefixed_source: &'a str = self.allocator.alloc_str(&prefixed);
            let parsed = Parser::new(self.allocator, prefixed_source, self.source_type)
                .with_options(parser_options())
                .parse();

            if parsed.errors.is_empty() {
                let mut body = parsed.program.body;
                body.remove(0);
                statements.extend(body);
                continue;
            }

            let wrapped = format!("function __oxc_splice__(){{;{source}}}");
            let wrapped_source: &'a str = self.allocator.alloc_str(&wrapped);
            let parsed = Parser::new(self.allocator, wrapped_source, self.source_type)
                .with_options(parser_options())
                .parse();

            if !parsed.errors.is_empty() {
                self.errors.extend(format_errors(&parsed.errors));
                return None;
            }

            let mut body = parsed.program.body;
            let Some(Statement::FunctionDeclaration(function)) = body.pop() else {
                self.errors
                    .push("Failed to parse statement splice".to_string());
                return None;
            };
            let Some(function_body) = function.unbox().body else {
                self.errors
                    .push("Failed to parse statement splice".to_string());
                return None;
            };
            let mut function_statements = function_body.unbox().statements;
            function_statements.remove(0);
            statements.extend(function_statements);
        }

        Some(statements)
    }

    fn property_replacements(&mut self) -> Option<OxcVec<'a, ObjectPropertyKind<'a>>> {
        let mut properties = OxcVec::new_in(self.allocator);

        for source in self.replacements.clone() {
            let wrapped = format!("({{{source}}})");
            let wrapped_source: &'a str = self.allocator.alloc_str(&wrapped);
            let mut program = self.parse_program(wrapped_source)?;
            let Some(Statement::ExpressionStatement(statement)) = program.body.pop() else {
                self.errors
                    .push("Expected an object property splice".to_string());
                return None;
            };

            let expression = match statement.unbox().expression {
                Expression::ParenthesizedExpression(parenthesized) => {
                    parenthesized.unbox().expression
                }
                expression => expression,
            };

            let Expression::ObjectExpression(object) = expression else {
                self.errors
                    .push("Expected an object property splice".to_string());
                return None;
            };

            let mut object = object.unbox();

            if object.properties.len() != 1 {
                self.errors
                    .push("Expected a single object property splice item".to_string());
                return None;
            }

            properties.push(object.properties.pop().unwrap());
        }

        Some(properties)
    }

    fn element_replacements(&mut self) -> Option<OxcVec<'a, ArrayExpressionElement<'a>>> {
        let mut elements = OxcVec::new_in(self.allocator);

        for source in self.replacements.clone() {
            let wrapped = format!("({source})");
            let wrapped_source: &'a str = self.allocator.alloc_str(&wrapped);
            let mut program = self.parse_program(wrapped_source)?;
            let Some(Statement::ExpressionStatement(statement)) = program.body.pop() else {
                self.errors
                    .push("Expected an array element splice".to_string());
                return None;
            };

            let expression = match statement.unbox().expression {
                Expression::ParenthesizedExpression(parenthesized) => {
                    parenthesized.unbox().expression
                }
                expression => expression,
            };

            elements.push(ArrayExpressionElement::from(expression));
        }

        Some(elements)
    }
}

impl<'a> VisitMut<'a> for SpliceVisitor<'a> {
    fn visit_statements(&mut self, statements: &mut OxcVec<'a, Statement<'a>>) {
        let old_statements = std::mem::replace(statements, OxcVec::new_in(self.allocator));

        for mut statement in old_statements {
            let is_placeholder = matches!(
                &statement,
                Statement::ExpressionStatement(expression_statement)
                    if matches!(
                        &expression_statement.expression,
                        Expression::Identifier(identifier)
                            if identifier.name.as_str() == self.placeholder
                    )
            );

            if is_placeholder {
                if let Some(replacements) = self.statement_replacements() {
                    statements.extend(replacements);
                }
            } else {
                walk_mut::walk_statement(self, &mut statement);
                statements.push(statement);
            }
        }
    }

    fn visit_object_property_kinds(&mut self, properties: &mut OxcVec<'a, ObjectPropertyKind<'a>>) {
        let old_properties = std::mem::replace(properties, OxcVec::new_in(self.allocator));

        for mut property in old_properties {
            let is_placeholder = matches!(
                &property,
                ObjectPropertyKind::ObjectProperty(object_property)
                    if object_property.shorthand
                        && matches!(
                            &object_property.key,
                            oxc_ast::ast::PropertyKey::StaticIdentifier(identifier)
                                if identifier.name.as_str() == self.placeholder
                        )
            );

            if is_placeholder {
                if let Some(replacements) = self.property_replacements() {
                    properties.extend(replacements);
                }
            } else {
                walk_mut::walk_object_property_kind(self, &mut property);
                properties.push(property);
            }
        }
    }

    fn visit_array_expression_elements(
        &mut self,
        elements: &mut OxcVec<'a, ArrayExpressionElement<'a>>,
    ) {
        let old_elements = std::mem::replace(elements, OxcVec::new_in(self.allocator));

        for mut element in old_elements {
            let is_placeholder = matches!(
                &element,
                ArrayExpressionElement::Identifier(identifier)
                    if identifier.name.as_str() == self.placeholder
            );

            if is_placeholder {
                if let Some(replacements) = self.element_replacements() {
                    elements.extend(replacements);
                }
            } else {
                walk_mut::walk_array_expression_element(self, &mut element);
                elements.push(element);
            }
        }
    }
}

pub fn codegen_native_impl<'a>(
    env: Env<'a>,
    source_term: Term<'a>,
    filename: &str,
    splices: Vec<(String, Vec<String>)>,
) -> NifResult<Term<'a>> {
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(filename).unwrap_or_default();
    let parsed = Parser::new(&allocator, source, source_type)
        .with_options(parser_options())
        .parse();

    if !parsed.errors.is_empty() {
        return error_to_term(env, &format_errors(&parsed.errors));
    }

    let mut program = parsed.program;

    for (name, replacements) in &splices {
        let replacement_sources = replacements
            .iter()
            .map(|source| allocator.alloc_str(source))
            .collect();

        let mut visitor = SpliceVisitor {
            allocator: &allocator,
            source_type: SourceType::default(),
            placeholder: format!("${name}"),
            replacements: replacement_sources,
            errors: Vec::new(),
        };
        visitor.visit_program(&mut program);

        if !visitor.errors.is_empty() {
            return error_to_term(env, &visitor.errors);
        }
    }

    let code = Codegen::new().build(&program).code;
    Ok((atoms::ok(), code).encode(env))
}
