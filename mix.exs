defmodule Moebius.Mixfile do
  use Mix.Project

  @version "0.0.1"

  def project do
    [app: :moebius,
     description: "A functional approach to data access with Elixir",
     version: @version,
     elixir: "~> 1.1",
     package: package,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(Mix.env),
     # ExDoc
     name: "Moebius",
     docs: [source_ref: "v#{@version}",
            main: Moebius.Query,
            source_url: "https://github.com/robconery/moebius",
            extras: ["README.md"]]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      mod: {Moebius, []},
      applications: [:logger, :postgrex, :tzdata]
    ]
  end

  defp deps(:dev) do
    deps(:prod)++[{:ex_doc, "~> 0.7", only: :dev},
      {:earmark, ">= 0.0.0"}]
  end

  defp deps(:test) do
    deps(:dev)
  end

  defp deps(:prod) do
    [{:postgrex, "~> 0.9.1"},{:timex, "~> 0.19.4"},{:inflex, "~> 1.5.0"}, {:poison, "~> 1.5"},{:json, "~> 0.3.0"}]
  end

  def package do
  [
    maintainers: ["Rob Conery"],
    licenses: ["New BSD"],
    links: %{"GitHub" => "https://github.com/robconery/moebius"}
  ]
end
end
