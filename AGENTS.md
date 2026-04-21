# AGENTS.md

## Build

```sh
OXC_EX_BUILD=1 mix compile   # build NIFs from source (requires Rust toolchain)
mix compile                   # use precompiled NIFs
mix test                      # full test suite
```

Set `OXC_EX_BUILD=1` for any compilation that touches Rust code.

## Architecture

Three separate Rust NIF crates:

- `native/oxc_ex_nif/` — parser, codegen, transform, minify, bundle (crates.io deps)
- `native/oxc_lint_nif/` — linter (git dep, `oxc_linter` not on crates.io)
- `native/oxc_fmt_nif/` — formatter (git dep, `oxc_formatter` not on crates.io)

Elixir modules:

- `lib/oxc.ex` — main API: parse, transform, minify, bundle, codegen, bind, splice, walk, postwalk, patch_string
- `lib/oxc/lint.ex` — `OXC.Lint.run/3`, `run!/3`
- `lib/oxc/format.ex` — `OXC.Format.run/3`, `run!/3`
- `lib/oxc/lint/rule.ex` — behaviour for custom Elixir lint rules

NIF options are read directly from BEAM terms via `Term::map_get` with
pre-declared atoms. No serde.

## Naming Conventions

- Submodules (`OXC.Lint`, `OXC.Format`) use `run/3` and `run!/3`
- Top-level `OXC` functions use operation names: `parse`, `transform`, `minify`, `bundle`
- Bang variants raise `OXC.Error` (never bare `RuntimeError`)

## Release

1. Bump `@version` in `mix.exs`
2. Update `CHANGELOG.md`
3. Commit: `git commit -m "Release vX.Y.Z"`
4. Tag and push: `git tag vX.Y.Z && git push && git push --tags`
5. Wait for the precompile workflow to finish (all 5 targets must pass)
6. Download checksums:
   ```sh
   OXC_EX_BUILD=1 mix rustler_precompiled.download OXC.Native --all
   OXC_EX_BUILD=1 mix rustler_precompiled.download OXC.Lint.Native --all
   OXC_EX_BUILD=1 mix rustler_precompiled.download OXC.Format.Native --all
   ```
7. Commit and push checksums: `git commit -am "Update precompiled NIF checksums for vX.Y.Z" && git push`
8. Publish: `mix hex.publish`

**Never force-push a release tag.** The precompile workflow triggers on tag
push. Force-pushing re-triggers it, producing new artifacts that overwrite
the previous ones with different checksums. If you need to fix a release,
publish a patch version instead.

**Checksums commit must come AFTER the CI build completes**, not before.
The tag points to the release commit (without checksums). The checksums
commit is a follow-up on master — it doesn't need a tag.
