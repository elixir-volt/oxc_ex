use std::path::Path;
use std::sync::Arc;

use oxc_allocator::Allocator;
use oxc_diagnostics::OxcDiagnostic;
use oxc_linter::PossibleFixes;
use oxc_linter::{
    AllowWarnDeny, ConfigStore, ConfigStoreBuilder, ExternalPluginStore, FixKind, LintFilter,
    LintFilterKind, LintOptions, LintPlugins, Linter, ModuleRecord,
};
use oxc_parser::{ParseOptions, Parser};
use oxc_semantic::SemanticBuilder;
use oxc_span::SourceType;
use rustler::{Binary, Encoder, Env, Error, NifResult, Term};

include!("generated_atoms.rs");

include!("generated_types.rs");

/// Parses plugin names with oxc_linter's own vocabulary, including its aliases.
fn lint_plugins(plugins: &[String]) -> Result<LintPlugins, String> {
    plugins
        .iter()
        .try_fold(LintPlugins::empty(), |plugins, name| {
            LintPlugins::try_from(name.as_str())
                .map(|plugin| plugins | plugin)
                .map_err(|()| format!("Unknown lint plugin {name:?}"))
        })
}

fn finding_severity(severity: AllowWarnDeny) -> FindingSeverity {
    match severity {
        AllowWarnDeny::Deny => FindingSeverity::Error,
        AllowWarnDeny::Allow | AllowWarnDeny::Warn => FindingSeverity::Warning,
    }
}

fn allow_warn_deny(severity: RuleSeverity) -> AllowWarnDeny {
    match severity {
        RuleSeverity::Allow => AllowWarnDeny::Allow,
        RuleSeverity::Warn => AllowWarnDeny::Warn,
        RuleSeverity::Deny => AllowWarnDeny::Deny,
    }
}

fn rule_severity(severity: AllowWarnDeny) -> RuleSeverity {
    match severity {
        AllowWarnDeny::Allow => RuleSeverity::Allow,
        AllowWarnDeny::Warn => RuleSeverity::Warn,
        AllowWarnDeny::Deny => RuleSeverity::Deny,
    }
}

/// Filters apply `all` first, then categories, then single rules, so the most
/// specific setting wins whatever order the rules arrive in.
fn filter_rank(filter: &LintFilter) -> u8 {
    match filter.kind() {
        LintFilterKind::All => 0,
        LintFilterKind::Category(_) => 1,
        LintFilterKind::Generic(_) | LintFilterKind::Rule(_, _) => 2,
    }
}

fn global_access(access: GlobalAccess) -> &'static str {
    match access {
        GlobalAccess::Readonly => "readonly",
        GlobalAccess::Writable => "writable",
        GlobalAccess::Off => "off",
    }
}

/// Byte-range labels with the primary label first.
fn labels(error: &OxcDiagnostic) -> Vec<(u32, u32, Option<String>)> {
    let mut labels = error.labels.clone().unwrap_or_default();
    labels.sort_by_key(|label| !label.primary());

    labels
        .iter()
        .map(|label| {
            let start = label.offset() as u32;
            (
                start,
                start + label.len() as u32,
                label.label().map(str::to_string),
            )
        })
        .collect()
}

fn fixes(fixes: &PossibleFixes) -> Vec<(u32, u32, String)> {
    let fixes = match fixes {
        PossibleFixes::None => &[][..],
        PossibleFixes::Single(fix) => std::slice::from_ref(fix),
        PossibleFixes::Multiple(fixes) => fixes.as_slice(),
    };

    fixes
        .iter()
        .map(|fix| (fix.span.start, fix.span.end, fix.content.to_string()))
        .collect()
}

struct LintConfig {
    config_store: ConfigStore,
    rule_severity_map: std::collections::HashMap<String, AllowWarnDeny>,
}

fn build_lint_config(
    plugins: &[String],
    rules: &[(String, RuleSeverity)],
    envs: &[String],
    globals: &[(String, GlobalAccess)],
) -> Result<LintConfig, String> {
    let lint_plugins = if plugins.is_empty() {
        LintPlugins::default()
    } else {
        lint_plugins(plugins)?
    };

    let mut external_plugin_store = ExternalPluginStore::default();

    let globals = globals
        .iter()
        .map(|(name, access)| (name.clone(), global_access(*access).into()))
        .collect::<serde_json::Map<_, _>>();

    let envs = envs
        .iter()
        .map(|name| (name.clone(), true.into()))
        .collect::<serde_json::Map<_, _>>();

    let oxlintrc = serde_json::from_value(serde_json::json!({"env": envs, "globals": globals}))
        .map_err(|e| format!("Invalid lint globals: {e}"))?;

    let mut builder =
        ConfigStoreBuilder::from_oxlintrc(false, oxlintrc, None, &mut external_plugin_store, None)
            .map_err(|e| format!("Failed to configure lint globals: {e}"))?
            .with_builtin_plugins(lint_plugins);

    let mut filters = rules
        .iter()
        .map(|(rule_name, severity)| {
            let kind = LintFilterKind::parse(std::borrow::Cow::Owned(rule_name.clone()))
                .map_err(|e| format!("Invalid rule filter '{rule_name}': {e}"))?;
            LintFilter::new(allow_warn_deny(*severity), kind)
                .map_err(|e| format!("Invalid lint filter '{rule_name}': {e}"))
        })
        .collect::<Result<Vec<_>, String>>()?;

    filters.sort_by_key(filter_rank);
    builder = builder.with_filters(&filters);

    let config = builder
        .build(&mut external_plugin_store)
        .map_err(|e| format!("Failed to build linter config: {e}"))?;

    let rule_severity_map = config
        .rules()
        .iter()
        .map(|(rule, severity)| (format_rule_enum_name(rule), *severity))
        .collect();

    Ok(LintConfig {
        config_store: ConfigStore::new(config, Default::default(), external_plugin_store),
        rule_severity_map,
    })
}

/// The type-aware (tsgolint) rules that `all` and category filters in `rules`
/// select from `plugins`, with their severities, resolved through oxlint's rule
/// registry. Without such filters no rules are selected, so callers that name
/// rules individually run only those.
fn type_aware_rules_impl(
    plugins: Vec<String>,
    rules: Vec<(String, RuleSeverity)>,
) -> NifResult<Result<Vec<(String, RuleSeverity)>, String>> {
    let selects_categories = rules.iter().any(|(name, _)| {
        matches!(
            LintFilterKind::parse(std::borrow::Cow::Owned(name.clone())),
            Ok(LintFilterKind::All | LintFilterKind::Category(_))
        )
    });

    if !selects_categories {
        return Ok(Ok(Vec::new()));
    }

    Ok(build_lint_config(&plugins, &rules, &[], &[]).map(|config| {
        config
            .config_store
            .rules()
            .iter()
            .filter(|(rule, _)| rule.is_tsgolint_rule())
            .map(|(rule, severity)| {
                (
                    format!("{}/{}", rule.plugin_name(), rule.name()),
                    rule_severity(*severity),
                )
            })
            .collect()
    }))
}

fn format_rule_enum_name(rule: &oxc_linter::rules::RuleEnum) -> String {
    let name = rule.name();
    let plugin = rule.plugin_name();
    if plugin == "eslint" {
        format!("eslint({name})")
    } else {
        format!("{plugin}({name})")
    }
}

fn format_rule_name(code: &oxc_diagnostics::OxcCode) -> String {
    let scope = code.scope.as_deref().unwrap_or("");
    let number = code.number.as_deref().unwrap_or("");
    if scope.is_empty() {
        number.to_string()
    } else if number.is_empty() {
        scope.to_string()
    } else {
        format!("{scope}({number})")
    }
}

fn source_from_term<'a>(term: Term<'a>) -> NifResult<Binary<'a>> {
    term.decode_as_binary()
}

fn binary_to_str<'a, 'b>(binary: &'b Binary<'a>) -> NifResult<&'b str> {
    std::str::from_utf8(binary).map_err(|_| Error::BadArg)
}

fn lint_impl<'a>(
    env: Env<'a>,
    source_term: Term<'a>,
    filename: &str,
    input: LintInput,
) -> NifResult<Term<'a>> {
    let source_binary = source_from_term(source_term)?;
    let source = binary_to_str(&source_binary)?;
    let path = Path::new(filename);
    let source_type = SourceType::from_path(path).unwrap_or_default();

    let allocator = Allocator::default();
    let ret = Parser::new(&allocator, source, source_type)
        .with_options(ParseOptions {
            parse_regular_expression: true,
            ..ParseOptions::default()
        })
        .parse();

    if !ret.errors.is_empty() {
        let errors: Vec<ParseError> = ret
            .errors
            .iter()
            .map(|error| ParseError {
                message: error.message.to_string(),
                labels: labels(error),
                help: error.help.as_ref().map(|h| h.to_string()),
            })
            .collect();
        return Ok((atoms::error(), errors).encode(env));
    }

    let lint_config =
        match build_lint_config(&input.plugins, &input.rules, &input.envs, &input.globals) {
            Ok(v) => v,
            Err(e) => return Ok((atoms::error(), vec![e]).encode(env)),
        };

    let fix_kind = if input.fix {
        FixKind::SafeFix
    } else {
        FixKind::None
    };

    let linter = Linter::new(
        LintOptions {
            fix: fix_kind,
            ..LintOptions::default()
        },
        lint_config.config_store,
        None,
    );

    let semantic = SemanticBuilder::new()
        .with_cfg(true)
        .build(&ret.program)
        .semantic;

    let module_record = Arc::new(ModuleRecord::default());
    let ctx_host = oxc_linter::ContextSubHost::new(semantic, module_record, 0, Default::default());
    let messages = linter.run(path, vec![ctx_host], &allocator);

    let diagnostics: Vec<Diagnostic> = messages
        .iter()
        .map(|msg| {
            let full_rule = format_rule_name(&msg.error.code);
            let severity = lint_config
                .rule_severity_map
                .get(&full_rule)
                .copied()
                .unwrap_or(AllowWarnDeny::Warn);

            Diagnostic {
                rule: full_rule,
                message: msg.error.message.to_string(),
                severity: finding_severity(severity),
                labels: match labels(&msg.error) {
                    labels if labels.is_empty() => vec![(msg.span.start, msg.span.end, None)],
                    labels => labels,
                },
                help: msg.error.help.as_ref().map(|h| h.to_string()),
                fixes: fixes(&msg.fixes),
            }
        })
        .collect();

    Ok((atoms::ok(), diagnostics).encode(env))
}

include!("generated_nifs.rs");

rustler::init!("Elixir.OXC.Lint.Native");
