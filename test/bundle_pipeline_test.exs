defmodule OXC.BundlePipelineTest do
  use ExUnit.Case, async: true

  alias OXC.Bundle

  test "bundles multiple virtual entries and returns generated outputs" do
    {:ok, result} =
      Bundle.new()
      |> Bundle.entries([
        %{
          name: "one",
          import: "one.js",
          source: "import { shared } from './shared.js'; console.log(shared);"
        },
        %{
          name: "two",
          import: "two.js",
          source: "import { shared } from './shared.js'; console.log(shared + 1);"
        }
      ])
      |> Bundle.files([{"shared.js", "export const shared = 41;"}])
      |> Bundle.format(:esm)
      |> Bundle.output(entry_file_names: "[name].js", chunk_file_names: "chunks/[name]-[hash].js")
      |> Bundle.run()

    entry_outputs = Enum.filter(result.outputs, &(&1.type == :entry))

    assert length(entry_outputs) == 2
    assert Enum.any?(entry_outputs, &(&1.file_name == "one.js"))
    assert Enum.any?(entry_outputs, &(&1.file_name == "two.js"))

    shared_chunk = Enum.find(result.outputs, &(&1.type == :chunk))
    assert shared_chunk
    assert "shared.js" in shared_chunk.module_ids
  end

  test "writes outputs when outdir is configured" do
    outdir = Path.join(System.tmp_dir!(), "oxc-bundle-#{System.unique_integer([:positive])}")

    {:ok, result} =
      Bundle.new()
      |> Bundle.entries([%{name: "app", import: "app.js", source: "console.log('ok');"}])
      |> Bundle.outdir(outdir)
      |> Bundle.output(entry_file_names: "[name].js")
      |> Bundle.run()

    output = Enum.find(result.outputs, &(&1.type == :entry))
    assert Path.expand(output.path) == Path.expand(Path.join(outdir, "app.js"))
    assert File.read!(output.path) == output.code

    File.rm_rf!(outdir)
  end
end
