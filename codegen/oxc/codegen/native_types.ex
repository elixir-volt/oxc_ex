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

  @type transform_input :: %{
          required(:jsx) => String.t(),
          required(:jsx_factory) => String.t(),
          required(:jsx_fragment) => String.t(),
          required(:import_source) => String.t(),
          required(:target) => String.t(),
          required(:sourcemap) => boolean()
        }

  @type minify_input :: %{required(:mangle) => boolean()}
end
