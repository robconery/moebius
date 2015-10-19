defmodule Moebius.Mixfile do
  use Mix.Project

  def project do
    [app: :moebius,
     description: "A functional approach to data access with Elixir",
     version: "0.0.1",
     elixir: "~> 1.1",
     package: package,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(Mix.env)]
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
    [{:postgrex, "~> 0.9.1"},{:timex, "~> 0.19.4"}]
  end

  def package do
  [
    maintainers: ["Rob Conery"],
    licenses: ["New BSD"],
    links: %{"GitHub" => "https://github.com/robconery/moebius"}
  ]
end
end
