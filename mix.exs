defmodule OXC.MixProject do
  use Mix.Project

  def project do
    [
      app: :oxc,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      lint: [
        "format --check-formatted",
        "credo --strict",
        "ex_dna",
        "dialyzer",
        "cmd cargo fmt --manifest-path native/oxc_ex_nif/Cargo.toml -- --check",
        "cmd cargo clippy --manifest-path native/oxc_ex_nif/Cargo.toml -- -D warnings"
      ]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.36.1"},
      {:rustler_precompiled, "~> 0.8"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false}
    ]
  end
end
