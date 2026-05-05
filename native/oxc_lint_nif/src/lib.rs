use std::path::Path;
use std::sync::Arc;

use oxc_allocator::Allocator;
use oxc_linter::{
    AllowWarnDeny, ConfigStore, ConfigStoreBuilder, ExternalPluginStore, FixKind, LintFilter,
    LintFilterKind, LintOptions, LintPlugins, Linter, ModuleRecord,
};
use oxc_parser::{ParseOptions, Parser};
use oxc_semantic::SemanticBuilder;
use oxc_span::SourceType;
use rustler::{Encoder, Env, NifMap, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        warn,
        deny,
        allow,
    }
}

#[derive(NifMap)]
struct Diagnostic {
    rule: String,
    message: String,
    severity: rustler::Atom,
    span: (u32, u32),
    labels: Vec<(u32, u32)>,
    help: Option<String>,
}

fn parse_plugins(plugin_strs: &[String]) -> LintPlugins {
    let mut plugins = LintPlugins::empty();
    for plugin in plugin_strs {
        match plugin.as_str() {
            "react" => plugins |= LintPlugins::REACT,
            "unicorn" => plugins |= LintPlugins::UNICORN,
            "typescript" => plugins |= LintPlugins::TYPESCRIPT,
            "oxc" => plugins |= LintPlugins::OXC,
            "import" => plugins |= LintPlugins::IMPORT,
            "jsdoc" => plugins |= LintPlugins::JSDOC,
            "jest" => plugins |= LintPlugins::JEST,
            "vitest" => plugins |= LintPlugins::VITEST,
            "jsx_a11y" | "jsx-a11y" => plugins |= LintPlugins::JSX_A11Y,
            "nextjs" | "next" => plugins |= LintPlugins::NEXTJS,
            "react_perf" | "react-perf" => plugins |= LintPlugins::REACT_PERF,
            "promise" => plugins |= LintPlugins::PROMISE,
            "node" => plugins |= LintPlugins::NODE,
            "vue" => plugins |= LintPlugins::VUE,
            _ => {}
        }
    }
    plugins
}

fn severity_atom(_env: Env<'_>, severity: AllowWarnDeny) -> rustler::Atom {
    match severity {
        AllowWarnDeny::Allow => atoms::allow(),
        AllowWarnDeny::Warn => atoms::warn(),
        AllowWarnDeny::Deny => atoms::deny(),
    }
}

fn parse_severity(s: &str) -> AllowWarnDeny {
    match s {
        "deny" | "error" => AllowWarnDeny::Deny,
        "warn" => AllowWarnDeny::Warn,
        "allow" | "off" => AllowWarnDeny::Allow,
        _ => AllowWarnDeny::Warn,
    }
}

struct LintConfig {
    config_store: ConfigStore,
    rule_severities: Vec<(String, AllowWarnDeny)>,
}

fn build_lint_config(plugins: &[String], rules: &[(String, String)]) -> Result<LintConfig, String> {
    let lint_plugins = if plugins.is_empty() {
        LintPlugins::default()
    } else {
        parse_plugins(plugins)
    };

    let mut external_plugin_store = ExternalPluginStore::default();
    let mut builder = ConfigStoreBuilder::default().with_builtin_plugins(lint_plugins);

    let mut rule_severities: Vec<(String, AllowWarnDeny)> = Vec::with_capacity(rules.len());

    for (rule_name, severity_str) in rules {
        let severity = parse_severity(severity_str.as_str());
        let filter_kind = LintFilterKind::parse(std::borrow::Cow::Owned(rule_name.clone()))
            .map_err(|e| format!("Invalid rule filter '{rule_name}': {e}"))?;
        let filter = LintFilter::new(severity, filter_kind)
            .map_err(|e| format!("Invalid lint filter '{rule_name}': {e}"))?;
        builder = builder.with_filters([&filter]);
        rule_severities.push((rule_name.clone(), severity));
    }

    let config = builder
        .build(&mut external_plugin_store)
        .map_err(|e| format!("Failed to build linter config: {e}"))?;

    Ok(LintConfig {
        config_store: ConfigStore::new(config, Default::default(), external_plugin_store),
        rule_severities,
    })
}

fn resolve_severity(rule_name: &str, rule_severities: &[(String, AllowWarnDeny)]) -> AllowWarnDeny {
    for (name, severity) in rule_severities.iter().rev() {
        if rule_name.contains(name.as_str()) {
            return *severity;
        }
    }
    AllowWarnDeny::Warn
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

#[rustler::nif(schedule = "DirtyCpu")]
fn lint<'a>(
    env: Env<'a>,
    source: &str,
    filename: &str,
    plugins: Vec<String>,
    rules: Vec<(String, String)>,
    fix: bool,
) -> NifResult<Term<'a>> {
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
        let error_msgs: Vec<String> = ret.errors.iter().map(|e| e.message.to_string()).collect();
        return Ok((atoms::error(), error_msgs).encode(env));
    }

    let lint_config = match build_lint_config(&plugins, &rules) {
        Ok(v) => v,
        Err(e) => return Ok((atoms::error(), vec![e]).encode(env)),
    };

    let fix_kind = if fix { FixKind::SafeFix } else { FixKind::None };

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
            let severity = resolve_severity(&full_rule, &lint_config.rule_severities);

            Diagnostic {
                rule: full_rule,
                message: msg.error.message.to_string(),
                severity: severity_atom(env, severity),
                span: (msg.span.start, msg.span.end),
                labels: msg
                    .error
                    .labels
                    .as_ref()
                    .map(|labels| {
                        labels
                            .iter()
                            .map(|l| (l.offset() as u32, (l.offset() + l.len()) as u32))
                            .collect()
                    })
                    .unwrap_or_default(),
                help: msg.error.help.as_ref().map(|h| h.to_string()),
            }
        })
        .collect();

    Ok((atoms::ok(), diagnostics).encode(env))
}

rustler::init!("Elixir.OXC.Lint.Native");
