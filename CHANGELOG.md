# Changelog

## 0.9.1

### Fixed

- Enable JSX parsing for `.js` files in formatter, matching oxfmt CLI behavior. Fixes formatting failures on projects using JSX in `.js` files (e.g. Plausible Analytics).

## 0.9.0

### Added

- `OXC.Format` — Prettier-compatible JS/TS formatter via oxfmt (~30× faster than Prettier). Separate `oxc_fmt_nif` Rust NIF crate. All oxfmt options supported: `print_width`, `tab_width`, `use_tabs`, `semi`, `single_quote`, `jsx_single_quote`, `trailing_comma`, `bracket_spacing`, `bracket_same_line`, `arrow_parens`, `end_of_line`, `quote_props`, `single_attribute_per_line`, `object_wrap`, `experimental_operator_position`, `experimental_ternaries`, `embedded_language_formatting`, `sort_imports`, `sort_tailwindcss`.
- `OXC.Lint.run!/3` — bang variant that raises `OXC.Error` on parse errors.

### Changed

- `OXC.Format.run!/3` raises `OXC.Error` instead of `RuntimeError`.

## 0.8.0

### Added

- `OXC.Lint.run/3` — lint JS/TS source with oxlint's 650+ built-in rules via a Rust NIF. Supports all oxlint plugins (react, typescript, unicorn, import, jsdoc, jest, vitest, jsx-a11y, nextjs, promise, node, vue) and configurable rule severities.
- `OXC.Lint.Rule` behaviour — write custom lint rules in Elixir that operate on the parsed ESTree AST. Rules use `OXC.walk/2`, `OXC.collect/2`, or `OXC.postwalk/3` for traversal and return diagnostics with spans.
- Built-in and custom rules run together in a single `OXC.Lint.run/3` call.

## 0.7.2

### Added

- `OXC.transform_many/2` — transform multiple files in parallel via a Rust rayon thread pool. Single NIF call, no BEAM scheduling overhead. 6.8x faster than sequential `transform/3` on 2000 files.

## 0.7.1

### Fixed

- Fix `parse/2` hitting serde_json recursion limit on deeply nested ASTs (e.g. large bundled output from Vue + reka-ui). Uses streaming deserializer with unbounded depth.

## 0.7.0

### Breaking changes

- AST `:type` and `:kind` values are now snake_case atoms instead of strings.
  `"ImportDeclaration"` → `:import_declaration`, `"const"` → `:const`, etc.
  Migration: update all pattern matches from `%{type: "ImportDeclaration"}` to `%{type: :import_declaration}`.
- All error tuples now return `{:error, [%{message: String.t()}]}` consistently.
  Previously `transform`, `minify`, `imports`, and `bundle` returned `{:error, [String.t()]}`.
- Bang functions (`parse!`, `transform!`, `minify!`, `bundle!`, etc.) now raise `OXC.Error` instead of `RuntimeError`.
  The exception has an `:errors` field with the structured error list.

### Added

- `OXC.collect_imports/2` — analyze imports with type info (`:static`/`:dynamic`), kind (`:import`/`:export`/`:export_all`), and byte offsets. Powered by a Rust NIF using OXC's visitor pattern.
- `OXC.rewrite_specifiers/3` — rewrite import/export specifiers in a single pass without Elixir-side AST walking.
- `:preamble` option for `bundle/2` — inject code at the top of the IIFE function body.
- `:treeshake` option for `bundle/2` — enable tree-shaking (default: `false`).
- `walk/2`, `postwalk/2`, `postwalk/3` now accept a list of nodes at the root level.
- `OXC.Error` exception module.

### Changed

- `collect/2` uses a recursive accumulator instead of creating an ETS table per call.
- `to_snake_atom` uses `Macro.underscore/1` instead of hand-rolled regex.
- `ImportInfo` uses `#[derive(NifMap)]` instead of a manual `Encoder` impl.
- `@type ast` tightened to `%{required(:type) => atom(), optional(atom()) => any()}`.
- `patch_string/2` deduplication behavior is now documented.
- Rust NIF split from a single 800-line `lib.rs` into `parse.rs`, `imports.rs`, `bundle.rs`, `options.rs`, `error.rs`.
- Import collector rewritten with `oxc_ast_visit::Visit` trait (~50 lines) replacing a hand-rolled 250-line AST walker.
- Bundle chunk selection no longer falls through to arbitrary chunks.

## 0.6.2

- Fix absolute temp dir paths leaking into `#region` comments in bundled output

## 0.6.1

- Added `:format` option to `bundle/2` — supports `:iife` (default), `:esm`, and `:cjs` output formats

## 0.6.0

### Breaking changes

- `OXC.bundle/2` now requires `entry: "..."` to identify the bundle entry module.
  Migration: change `OXC.bundle(files)` to `OXC.bundle(files, entry: "main.ts")`.

### Changed

- `OXC.bundle/2` now uses Rolldown/OXC for bundling.
- Internal Rustler boundary code for `parse`, `transform`, `minify`, and `bundle` was simplified with serde-based term encoding/decoding.

## 0.5.4

- Handle `export default <expression>` in bundler — emits `var _default = <expr>` instead of dropping the expression. Fixes Vue SFC compiled output losing the component object.

## 0.5.3

- Fix `export { local as default }` producing `var default = local` (syntax error). The bundler's alias emitter now uses `_default` for the reserved word `default`.

## 0.5.2

- (yanked — fix was incomplete)

## 0.5.1

- Handle circular dependencies in bundler's topological sort — modules in a cycle are appended in sorted order instead of raising an error. Enables bundling Vue, Reka UI, and other frameworks with circular imports.

## 0.5.0

- Initial precompiled NIF release (aarch64-apple-darwin, x86_64-apple-darwin, x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu, x86_64-unknown-linux-musl)
- Move to elixir-volt org

## 0.4.0

- `OXC.bundle/2` — bundle multiple JS/TS modules into a single IIFE with topological sorting and import resolution
- `OXC.imports/2` — extract import specifiers from source
- `OXC.postwalk/3` — AST traversal with accumulator for source patching
- `OXC.patch_string/2` — apply byte-offset patches
- Compile-time replacements via `:define` option
- Source map support in bundle and minify
