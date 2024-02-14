defmodule Moebius.Mixfile do
  use Mix.Project

  @version "4.0.0"

  def project do
    [
      app: :moebius,
      description: "A functional approach to data access with Elixir",
      version: @version,
      elixir: "~> 1.15",
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      # ExDoc
      name: "Moebius",
      docs: [
        source_ref: "v#{@version}",
        main: Moebius.Query,
        source_url: "https://github.com/robconery/moebius",
        extras: ["README.md"]
      ],
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger, :postgrex]
    ]
  end

  defp deps do
    [
      {:postgrex, "~> 0.17.4"},
      {:jason, "~> 1.4"},

      # Dev & Test
      {:ex_doc, "~> 0.31.1", only: [:dev, :docs]},
      {:earmark, "~> 1.4.46", only: [:dev, :docs]},
      {:credo, "~> 1.7.4", only: [:dev, :test]},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
    ]
  end

  def package do
    [
      maintainers: ["Rob Conery", "Chase Pursley"],
      licenses: ["New BSD"],
      links: %{"GitHub" => "https://github.com/robconery/moebius"}
    ]
  end

  defp aliases do
    [
      "moebius.setup": ["moebius.create", "moebius.migrate", "moebius.seed"],
      "moebius.reset": ["moebius.drop", "moebius.setup"],
      quality: [
        "format --check-formatted",
        "sobelow --config",
        "credo --only warning"
      ]
    ]
  end

  defp elixirc_paths(_), do: ["lib"]
end
