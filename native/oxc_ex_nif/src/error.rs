use oxc_diagnostics::OxcDiagnostic;
use rustler::{Encoder, Env, NifMap, NifResult, Term};

use crate::atoms;

/// A raw error: message, help, and byte-range labels with the primary label first.
///
/// `OXC.Diagnostic` turns these into `Code.diagnostic` maps on the Elixir side.
#[derive(Clone, NifMap)]
pub struct Diagnostic {
    message: String,
    help: Option<String>,
    labels: Vec<(usize, usize, Option<String>)>,
}

impl From<&OxcDiagnostic> for Diagnostic {
    fn from(error: &OxcDiagnostic) -> Self {
        let mut labels = error.labels.clone().unwrap_or_default();
        labels.sort_by_key(|label| !label.primary());

        Self {
            message: error.message.to_string(),
            help: error.help.as_ref().map(ToString::to_string),
            labels: labels
                .iter()
                .map(|label| {
                    let start = label.offset();
                    (
                        start,
                        start + label.len(),
                        label.label().map(str::to_string),
                    )
                })
                .collect(),
        }
    }
}

impl From<String> for Diagnostic {
    fn from(message: String) -> Self {
        Self {
            message,
            help: None,
            labels: Vec::new(),
        }
    }
}

pub fn diagnostics(errors: &[OxcDiagnostic]) -> Vec<Diagnostic> {
    errors.iter().map(Diagnostic::from).collect()
}

/// Messages only, for errors whose ranges refer to generated source.
pub fn format_errors(errors: &[OxcDiagnostic]) -> Vec<String> {
    errors.iter().map(ToString::to_string).collect()
}

pub fn error_to_term<'a, D>(env: Env<'a>, errors: &[D]) -> NifResult<Term<'a>>
where
    D: Clone + Into<Diagnostic>,
{
    let errors: Vec<Diagnostic> = errors.iter().cloned().map(Into::into).collect();
    Ok((atoms::error(), errors).encode(env))
}
