# oxc_ex_nif

Rust NIF for the [OXC](https://hex.pm/packages/oxc) Elixir package.

Wraps [oxc_parser](https://crates.io/crates/oxc_parser), [oxc_transformer](https://crates.io/crates/oxc_transformer), [oxc_minifier](https://crates.io/crates/oxc_minifier), and [oxc_codegen](https://crates.io/crates/oxc_codegen) via [Rustler](https://github.com/rusterlium/rustler).

This crate is not meant to be used directly — it compiles automatically as part of `mix compile`.
