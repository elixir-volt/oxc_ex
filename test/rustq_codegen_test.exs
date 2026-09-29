# RustQ is only a dependency on Elixir 1.19+, see codegen_and_analysis_deps/0 in mix.exs.
if Code.ensure_loaded?(RustQ.Test) do
  Code.require_file("../codegen/oxc/codegen/lint_types.ex", __DIR__)

  defmodule OXC.RustQCodegenTest do
    use RustQ.Test, async: true

    test "derives lint boundary maps for the existing precompiled crate" do
      source = RustQ.Native.source(OXC.Codegen.LintTypes)

      assert source =~ "pub struct LintInput"
      assert source =~ "pub struct Diagnostic"
      assert source =~ "rustler::NifMap"
      assert source =~ "rustler::NifUnitEnum"
      assert source =~ "pub severity: FindingSeverity"
      assert source =~ "pub rules: Vec<(String, RuleSeverity)>"
      assert source =~ "pub plugins: Vec<String>"
      assert RustQ.valid?(source, "oxc_lint_types.rs")
    end
  end
end
