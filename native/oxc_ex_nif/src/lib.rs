mod bundle;
mod codegen;
mod error;
mod imports;
mod options;
mod parse;
mod transform_many;

use rustler::{Env, NifResult, Term};

use bundle::{bundle_entry_impl, bundle_impl, bundle_run_impl};
use codegen::codegen_impl;
use imports::select_impl;
use parse::{minify_impl, parse_impl, transform_impl, valid_impl};
use transform_many::transform_many_impl;

include!("generated_atoms.rs");
include!("generated_nifs.rs");

rustler::init!("Elixir.OXC.Native");
