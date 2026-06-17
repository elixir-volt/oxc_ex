defmodule OXC.Bundle.Entry do
  @moduledoc "Bundle entry configuration."

  defstruct name: nil, import: nil, source: nil

  @type t :: %__MODULE__{name: String.t() | nil, import: String.t(), source: iodata() | nil}

  def new(%__MODULE__{} = entry), do: entry
  def new(import) when is_binary(import), do: %__MODULE__{import: import}

  def new({name, import}) when is_binary(name) and is_binary(import),
    do: %__MODULE__{name: name, import: import}

  def new({import, source}) when is_binary(import),
    do: %__MODULE__{import: import, source: source}

  def new({name, import, source}), do: %__MODULE__{name: name, import: import, source: source}

  def new(map) when is_map(map) do
    %__MODULE__{
      name: Map.get(map, :name) || Map.get(map, "name"),
      import: Map.get(map, :import) || Map.get(map, "import"),
      source: Map.get(map, :source) || Map.get(map, "source")
    }
  end

  def to_native(%__MODULE__{} = entry) do
    %{name: entry.name, import: entry.import, source: entry.source}
  end
end
