defmodule LoggerGraylogBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_graylog_backend,
      version: "0.1.0",
      elixir: "~> 1.6-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.18", only: :dev, runetime: false},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:jason, "~> 1.0-rc"},
      {:optium, "~> 0.3"},
      {:backoff, "~> 1.1"}
    ]
  end
end
