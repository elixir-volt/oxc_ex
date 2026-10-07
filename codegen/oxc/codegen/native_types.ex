defmodule OXC.Codegen.NativeTypes do
  @moduledoc false
  # Boundary types of the main NIF crate, generated into
  # `native/oxc_ex_nif/src/generated_types.rs`. An option map declared here
  # arrives in Rust as a struct, with no term reading by hand.

  use RustQ.Native,
    build: false,
    load: false,
    crate: :oxc_ex_native_types

  @type declarations_input :: %{
          required(:strip_internal) => boolean(),
          required(:sourcemap) => boolean()
        }
end
