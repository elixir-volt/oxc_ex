# OXC

Elixir bindings for the [OXC](https://oxc.rs) JavaScript toolchain via Rust NIFs.

Parse, transform, and minify JavaScript/TypeScript at native speed.

## Features

- **Parse** JS/TS/JSX/TSX into ESTree AST (maps with atom keys, snake_case types)
- **Transform** TypeScript → JavaScript, JSX → `createElement`/`jsx` calls
- **Minify** with dead code elimination, constant folding, and variable mangling
- **Bundle** multiple TS/JS modules into a single IIFE with dependency resolution
- **Rewrite specifiers** — rewrite import/export paths in a single pass
- **Collect imports** — typed import analysis (static/dynamic, import/export/export_all)
- **Walk/Collect** helpers for AST traversal and node filtering
- **Postwalk** with accumulator for AST-based source patching (like `Macro.postwalk/3`)
- **Patch string** — apply byte-offset patches to source (like `Sourceror.patch_string/2`)
- **Import extraction** — fast NIF-level import specifier extraction

## Installation

```elixir
def deps do
  [
    {:oxc, "~> 0.7.0"}
  ]
end
```

Precompiled NIFs are available for macOS (aarch64, x86_64) and Linux (aarch64, x86_64, musl).
Building from source requires a Rust toolchain (`rustup` recommended).

## Usage

### Parse

```elixir
{:ok, ast} = OXC.parse("const x = 1 + 2", "test.js")
ast.type
# :program

[stmt] = ast.body
stmt.expression
# %{type: :binary_expression, operator: "+", left: %{value: 1}, right: %{value: 2}}
```

File extension determines the dialect — `.js`, `.jsx`, `.ts`, `.tsx`:

```elixir
{:ok, ast} = OXC.parse("const x: number = 42", "test.ts")
{:ok, ast} = OXC.parse("<App />", "component.tsx")
```

AST node `:type` and `:kind` values are snake_case atoms (e.g. `:import_declaration`, `:variable_declaration`, `:const`).

### Transform

Strip TypeScript types and transform JSX:

```elixir
{:ok, js} = OXC.transform("const x: number = 42", "test.ts")
# "const x = 42;\n"

{:ok, js} = OXC.transform("<App />", "app.tsx")
# Uses automatic JSX runtime by default

{:ok, js} = OXC.transform("<App />", "app.jsx", jsx: :classic)
# Uses React.createElement
```

With source maps:

```elixir
{:ok, %{code: js, sourcemap: map}} = OXC.transform(code, "app.ts", sourcemap: true)
```

Target specific environments:

```elixir
{:ok, js} = OXC.transform("const x = a ?? b", "test.js", target: "es2019")
# Nullish coalescing lowered to ternary
```

Custom JSX import source (Vue, Preact, etc.):

```elixir
{:ok, js} = OXC.transform("<div />", "app.jsx", import_source: "vue")
# Imports from vue/jsx-runtime instead of react/jsx-runtime
```

### Minify

```elixir
{:ok, min} = OXC.minify("const x = 1 + 2; console.log(x);", "test.js")
# Constants folded, whitespace removed, variables mangled

{:ok, min} = OXC.minify(code, "test.js", mangle: false)
# Compress without renaming variables
```

### Import Extraction

Fast NIF-level extraction of import specifiers — skips full AST serialization:

```elixir
{:ok, imports} = OXC.imports("import { ref } from 'vue'\nimport { h } from 'preact'", "test.ts")
# ["vue", "preact"]
```

Type-only imports are excluded automatically:

```elixir
{:ok, imports} = OXC.imports("import type { Ref } from 'vue'\nimport { ref } from 'vue'", "test.ts")
# ["vue"]
```

### Typed Import Analysis

Collect imports with type information, byte offsets, and kind:

```elixir
source = "import { ref } from 'vue'\nexport { foo } from './foo'\nimport('./lazy')"
{:ok, imports} = OXC.collect_imports(source, "test.js")
# [
#   %{specifier: "vue", type: :static, kind: :import, start: 20, end: 25},
#   %{specifier: "./foo", type: :static, kind: :export, start: 47, end: 54},
#   %{specifier: "./lazy", type: :dynamic, kind: :import, start: 62, end: 70}
# ]
```

### Rewrite Specifiers

Rewrite import/export specifiers in a single pass without AST walking:

```elixir
source = "import { ref } from 'vue'\nimport a from './utils'"

{:ok, result} = OXC.rewrite_specifiers(source, "test.js", fn
  "vue" -> {:rewrite, "/@vendor/vue.js"}
  _ -> :keep
end)
# "import { ref } from '/@vendor/vue.js'\nimport a from './utils'"
```

Handles `ImportDeclaration`, `ExportNamedDeclaration`, `ExportAllDeclaration`, and dynamic `import()`.

### Validate

Fast syntax check without building an AST:

```elixir
OXC.valid?("const x = 1", "test.js")
# true

OXC.valid?("const = ;", "bad.js")
# false
```

### AST Traversal

```elixir
{:ok, ast} = OXC.parse("import a from 'a'; import b from 'b'; const x = 1;", "test.js")

# Walk every node
OXC.walk(ast, fn
  %{type: :identifier, name: name} -> IO.puts(name)
  _ -> :ok
end)

# Collect specific nodes
imports = OXC.collect(ast, fn
  %{type: :import_declaration} = node -> {:keep, node}
  _ -> :skip
end)
```

### AST Postwalk and Source Patching

Rewrite source code by walking the AST and collecting byte-offset patches:

```elixir
source = "import { ref } from 'vue'\nimport { h } from 'preact'"
{:ok, ast} = OXC.parse(source, "test.ts")

{_ast, patches} =
  OXC.postwalk(ast, [], fn
    %{type: :import_declaration, source: %{value: "vue", start: s, end: e}}, acc ->
      {nil, [%{start: s, end: e, change: "'/@vendor/vue.js'"} | acc]}
    node, acc ->
      {node, acc}
  end)

rewritten = OXC.patch_string(source, patches)
# "import { ref } from '/@vendor/vue.js'\nimport { h } from 'preact'"
```

`postwalk/2` visits nodes depth-first (children before parent), like `Macro.postwalk/2`.
`postwalk/3` adds an accumulator for collecting data during traversal.
`patch_string/2` applies patches in reverse offset order so positions stay valid.

All traversal functions (`walk/2`, `postwalk/2`, `postwalk/3`) accept either a single AST node or a list of nodes.

### Bundle

Bundle multiple TypeScript/JavaScript modules into a single IIFE script.
Treats the provided files as a virtual project, resolves their imports,
transforms TS/JSX, and bundles the result:

```elixir
files = [
  {"event.ts", "export class Event { type: string; constructor(t: string) { this.type = t } }"},
  {"target.ts", "import { Event } from './event'\nexport class Target extends Event {}"}
]

{:ok, js} = OXC.bundle(files, entry: "target.ts")
```

Options:

```elixir
# Minify with variable mangling
{:ok, js} = OXC.bundle(files, entry: "target.ts", minify: true)

# Tree-shaking (remove unused exports)
{:ok, js} = OXC.bundle(files, entry: "target.ts", treeshake: true)

# Inject code at the top of the IIFE body
{:ok, js} = OXC.bundle(files, entry: "app.ts", preamble: "const { ref } = Vue;")

# Compile-time replacements (like esbuild/Bun define)
{:ok, js} = OXC.bundle(files, entry: "target.ts", define: %{"process.env.NODE_ENV" => ~s("production")})

# Source maps
{:ok, %{code: js, sourcemap: map}} = OXC.bundle(files, entry: "target.ts", sourcemap: true)

# Output format: :iife (default), :esm, or :cjs
{:ok, js} = OXC.bundle(files, entry: "target.ts", format: :esm)

# Remove console.* calls
{:ok, js} = OXC.bundle(files, entry: "target.ts", minify: true, drop_console: true)

# Target-specific downleveling
{:ok, js} = OXC.bundle(files, entry: "target.ts", target: "es2020")

# Banner and footer
{:ok, js} = OXC.bundle(files, entry: "target.ts", banner: "/* MIT */", footer: "/* v1.0 */")
```

### Bang Variants

All functions have bang variants that raise `OXC.Error` on failure:

```elixir
ast = OXC.parse!("const x = 1", "test.js")
js = OXC.transform!("const x: number = 42", "test.ts")
min = OXC.minify!("const x = 1 + 2;", "test.js")
imports = OXC.imports!("import { ref } from 'vue'", "test.ts")
```

### Error Handling

All functions return `{:ok, result}` or `{:error, errors}` where errors are
maps with a `:message` key:

```elixir
{:error, [%{message: "Expected a semicolon or ..."}]} = OXC.parse("const = ;", "bad.js")
```

## How It Works

OXC is a collection of high-performance JavaScript tools written in Rust.
This library wraps `oxc_parser`, `oxc_transformer`, `oxc_minifier`,
`oxc_transformer_plugins`, and `oxc_codegen` via [Rustler](https://github.com/rusterlium/rustler) NIFs,
and uses Rolldown/OXC for `bundle/2`.

All NIF calls run on the dirty CPU scheduler so they don't block the BEAM.
The parser produces ESTree JSON via OXC's serializer, Rustler encodes it
as BEAM terms, and the Elixir wrapper normalizes AST keys to atoms with
snake_case type values.

## License

MIT
