defmodule Moebius.Mixfile do
  use Mix.Project

  @version "5.0.1"

  def project do
    [
      app: :moebius,
      description: "A functional approach to data access with Elixir",
      version: @version,
      elixir: "~> 1.15",
      package: package(),
      start_permanent: Mix.env() == :prod,
      # ExDoc
      name: "Moebius",
      docs: [
        source_ref: "v#{@version}",
        source_url: "https://github.com/robconery/moebius",
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "SECURITY.md",
          "CODE_OF_CONDUCT.md",
          "LICENSE"
        ]
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
      {:epgsql, "~> 4.8"},
      {:pooler, "~> 1.7"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 3.0"},

      # Dev & Test
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false}
    ]
  end

  defp package() do
    [
      files:
        ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
