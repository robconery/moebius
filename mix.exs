defmodule Moebius.Mixfile do
  use Mix.Project

  @version "4.2.0"

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
        source_url: "https://github.com/robconery/moebius",
        extras: ["README.md"]
      ],
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:postgrex, "~> 0.19.2"},
      {:jason, "~> 1.4.4"},

      # Dev & Test
      {:ex_doc, "~> 0.34.2", only: :dev},
      {:credo, "~> 1.7.8", only: [:dev, :test]},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp package() do
    [
      files: ~w(lib test .formatter.exs mix.exs README* LICENSE*),
      maintainers: ["Rob Conery", "Chase Pursley"],
      licenses: ["MIT"],
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
