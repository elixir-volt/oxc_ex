defmodule OXC.Test.Command do
  @moduledoc false

  @spec write!(String.t(), String.t(), keyword()) :: String.t()
  def write!(dir, name, opts) do
    opts = Keyword.validate!(opts, [:unix, :windows])

    case :os.type() do
      {:win32, _name} -> write_windows!(dir, name, Keyword.fetch!(opts, :windows))
      _other -> write_unix!(dir, name, Keyword.fetch!(opts, :unix))
    end
  end

  defp write_unix!(dir, name, script) do
    executable = Path.join(dir, name)
    File.write!(executable, script)
    File.chmod!(executable, 0o755)
    executable
  end

  defp write_windows!(dir, name, script) do
    script_path = Path.join(dir, "#{name}.ps1")
    executable = Path.join(dir, "#{name}.cmd")
    File.write!(script_path, script)

    native_script_path = script_path |> String.replace("/", "\\") |> String.replace("%", "%%")

    File.write!(
      executable,
      ~s(@powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "#{native_script_path}" %*\r\n)
    )

    executable
  end
end
