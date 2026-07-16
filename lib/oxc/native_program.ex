defmodule OXC.NativeProgram do
  @moduledoc false

  @enforce_keys [:source, :filename]
  defstruct [:source, :filename, splices: []]

  @type t :: %__MODULE__{
          source: String.t(),
          filename: String.t(),
          splices: [{String.t(), [String.t()]}]
        }
end
