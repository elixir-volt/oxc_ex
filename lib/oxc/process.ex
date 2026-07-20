defmodule OXC.Process do
  @moduledoc false

  @spec run(String.t(), [String.t()], keyword()) :: {binary(), integer()}
  def run(executable, args, opts) do
    opts = Keyword.validate!(opts, [:stdin_file, :stderr_file, :cd])
    stdin_file = Keyword.fetch!(opts, :stdin_file)
    stderr_file = Keyword.fetch!(opts, :stderr_file)
    cwd = Keyword.get_lazy(opts, :cd, &File.cwd!/0)

    case :os.type() do
      {:win32, _name} -> run_windows(executable, args, stdin_file, stderr_file, cwd)
      _other -> run_unix(executable, args, stdin_file, stderr_file, cwd)
    end
  end

  defp run_unix(executable, args, stdin_file, stderr_file, cwd) do
    command_args = ["sh", stdin_file, stderr_file, executable | args]

    System.cmd(
      "sh",
      [
        "-c",
        "payload=$1; stderr=$2; shift 2; exec \"$@\" < \"$payload\" 2> \"$stderr\""
        | command_args
      ],
      cd: cwd,
      stderr_to_stdout: false
    )
  end

  defp run_windows(executable, args, stdin_file, stderr_file, cwd) do
    stdout_file = tmp_path("oxc-process-stdout")
    command_file = tmp_path("oxc-process-runner", ".cmd")

    invocation =
      [windows_path(executable) | args]
      |> Enum.map_join(" ", &windows_command_arg/1)
      |> Kernel.<>(" < #{stdin_file |> windows_path() |> windows_command_arg()}")
      |> Kernel.<>(" > #{stdout_file |> windows_path() |> windows_command_arg()}")
      |> Kernel.<>(" 2> #{stderr_file |> windows_path() |> windows_command_arg()}")

    # Omitting `call` avoids cmd.exe expanding arguments a second time. If the
    # executable is itself a batch wrapper, control transfers to it and its exit
    # status becomes the runner's status.
    File.write!(command_file, "@echo off\r\n#{invocation}\r\nexit /b %errorlevel%\r\n")

    try do
      {_output, status} =
        System.cmd("cmd.exe", ["/d", "/s", "/c", windows_path(command_file)],
          cd: cwd,
          stderr_to_stdout: false
        )

      {read_file(stdout_file), status}
    after
      File.rm(command_file)
      File.rm(stdout_file)
    end
  end

  defp windows_command_arg(arg) do
    escaped = arg |> String.replace("%", "%%") |> String.replace(~s("), ~s(""))
    ~s("#{escaped}")
  end

  defp windows_path(path), do: String.replace(path, "/", "\\")

  defp tmp_path(prefix, extension \\ "") do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}#{extension}")
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> ""
    end
  end
end
