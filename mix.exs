defmodule Artificery.MixProject do
  use Mix.Project

  def project do
    [
      app: :artificery,
      version: "0.4.2",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env),
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs,
        "eqc.install": :test
      ]
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:docs], runtime: false},
      {:eqc_ex, "~> 1.4", only: [:test], runtime: false}
    ]
  end

  defp description, do: "A toolkit for terminal user interfaces in Elixir"

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["Apache 2.0"],
      links: %{
        GitHub: "https://github.com/bitwalker/artificery",
        Issues: "https://github.com/bitwalker/artificery/issues"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
