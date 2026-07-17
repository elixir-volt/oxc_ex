Code.require_file("../codegen/oxc/codegen/lint_types.ex", __DIR__)

defmodule OXC.RustQCodegenTest do
  use RustQ.Test, async: true

  test "derives lint boundary maps for the existing precompiled crate" do
    source = RustQ.Native.source(OXC.Codegen.LintTypes)

    assert source =~ "pub struct LintInput"
    assert source =~ "pub struct Diagnostic"
    assert source =~ "rustler::NifMap"
    assert source =~ "pub severity: Atom"
    assert RustQ.valid?(source, "oxc_lint_types.rs")
  end
end
