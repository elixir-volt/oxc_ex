mod bundle;
mod codegen;
mod error;
mod imports;
mod options;
mod parse;
mod transform_many;

include!("generated_atoms.rs");

rustler::init!("Elixir.OXC.Native");
