# Changelog

## Unreleased

## 0.17.2 - 2026-06-19

### Added

- Add `:dynamic_import_templates` selector for template-literal dynamic `import(...)` expressions.
- Add `:require_calls` selector for CommonJS `require("...")` calls.

## 0.17.0 - 2026-06-19

### Breaking changes

- Remove `OXC.imports/2`, `OXC.imports!/2`, `OXC.collect_imports/2`, and `OXC.collect_imports!/2`; use `OXC.select/3` with selector atoms instead.

### Added

- Add `OXC.select/3` for compact parser-backed event selection.
- Add selector atoms for import sources, import specifiers, asset URLs, workers, glob imports, and `import.meta.env` references.

### Changed

- `OXC.rewrite_specifiers/3` now uses parser-backed selector events internally.
- Native import/source-reference selection now uses the shared `rustler_match_spec` crate.

### Fixed

- Recognize generated `{}.url` bases when selecting worker URL references from bundled output.

## 0.16.0

### Added

- Add `OXC.Bundle`, a composable bundling pipeline that returns all Rolldown chunks and assets from multi-entry builds.
- Add bundle output metadata for generated chunks, assets, imports, dynamic imports, exports, sourcemaps, and optional output paths.

### Changed

- Upgrade Rolldown bundling dependencies to 1.1.
- Decode native options directly from BEAM maps instead of routing through `serde_json`.

### Fixed

- Prevent `serde_json::Number` internals from leaking into parsed AST terms when dependencies enable arbitrary-precision JSON numbers.
- Fix code generation for `if` statements with nil `alternate` branches.

## 0.15.1

### Fixed

- `OXC.Lint.run/2` now reports nonzero `tsgolint` exits with stderr output, including panics from unsupported input files, instead of treating empty or malformed output as a clean type-aware lint result.

## 0.15.0

### Added

- `OXC.Lint.run/2` supports file-list type-aware linting through `tsgolint` headless mode with `type_aware: true`.
- Type-aware linting supports `type_check`, `source_overrides`, fixes, suggestions, and normalized diagnostics.

## 0.14.0

### Added

- Source-taking APIs now accept `iodata()` across parse, transform, minify, import collection, lint, format, source patching, and virtual bundle inputs.

### Changed

- `OXC.patch_string/2` now builds patched output with iodata internally before flattening once.
- Virtual bundle file sources are streamed from iodata directly into temporary files instead of being flattened first.

### Fixed

- Lint category filters (e.g. `"correctness" => :deny`) now return the configured severity instead of always `:warn`.

## 0.13.0

### Added

- `module_types` option for `OXC.bundle/2` — map file extensions to loaders (`:empty`, `:dataurl`, `:base64`, `:binary`, `:text`, `:css`, `:asset`, etc.). Unblocks bundling packages that import binary files like fonts from CSS.

### Changed

- Upgraded OXC crates from 0.129 to 0.130.
- Removed unused Cargo dependencies (`oxc_resolver`, `oxc_transformer_plugins`).
- `mix lint` / `mix ci` now checks clippy and rustfmt for all three NIF crates.

### Fixed

- Resolved all clippy warnings under `-D warnings`.

## 0.12.1

### Fixed

- `OXC.bundle/2` with `sourcemap: true` no longer fails when Rolldown omits the source map for empty bundle output ([#4](https://github.com/elixir-volt/oxc_ex/issues/4)).

## 0.12.0

### Changed

- Upgraded OXC toolchain from 0.117 to 0.129 — 12 releases of parser, transformer, minifier, and codegen improvements.
- Upgraded OXC formatter from crates_v0.117.0 to crates_v0.129.0.
- Upgraded OXC linter from crates_v0.117.0 to crates_v0.129.0 (oxc_linter 1.62.0).
- Upgraded oxc_sourcemap from 6 to 6.1.

## 0.11.0

### Added

- `OXC.bundle/2` accepts filesystem entry paths, e.g. `OXC.bundle("src/main.ts", cwd: project_dir)`, alongside virtual `{filename, source}` projects.
- Bundle resolver options for Rolldown: `:conditions`, `:main_fields`, and `:modules`.
- Bundle output options for Rolldown: `:exports` and `:preserve_entry_signatures`.

### Changed

- Removed the binding-level bare import auto-externalization pass; Rolldown now handles unresolved externals directly.

## 0.10.0

### Added

- `OXC.codegen/1` / `codegen!/1` — generate JavaScript source from ESTree AST maps via OXC's code generator. Proper operator precedence, formatting, and semicolons. Roundtrips with `parse/2`.
- `OXC.bind/2` — substitute `$placeholders` in a parsed AST with identifiers, literals (including recursive maps/lists → JS objects/arrays), parsed expressions, or raw AST nodes.
- `OXC.splice/3` — expand a `$placeholder` statement, object property, or array element into a list of nodes. Strings are auto-parsed as JS.
- `:external` option for `OXC.bundle/2` — list of bare specifiers to preserve as `import` statements in the output. Merged with auto-detected ESM externals.

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
