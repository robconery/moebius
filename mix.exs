defmodule Moebius.Mixfile do
  use Mix.Project

  @version "3.0.1"

  def project do
    [
      app: :moebius,
       description: "A functional approach to data access with Elixir",
       version: @version,
       elixir: "~> 1.4",
       package: package(),
       build_embedded: Mix.env == :prod,
       start_permanent: Mix.env == :prod,
       # ExDoc
       name: "Moebius",
       docs: [source_ref: "v#{@version}",
              main: Moebius.Query,
              source_url: "https://github.com/robconery/moebius",
              extras: ["README.md"]],
       deps: deps()]
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
    [{:postgrex, "~> 0.13.1"},
     {:inflex, "~> 1.5.0"},
     {:poolboy,       ">= 0.0.0"},
     {:poison, "~> 3.0.0"},
     {:ex_doc, "~> 0.11.2", only: [:dev, :docs]},
     {:earmark, "~> 0.2.0", only: [:dev, :docs]},
     {:credo, "~> 0.2.5", only: [:dev, :test]}]
  end

  def package do
    [maintainers: ["Rob Conery"],
     licenses: ["New BSD"],
     links: %{"GitHub" => "https://github.com/robconery/moebius"}]
  end
end
