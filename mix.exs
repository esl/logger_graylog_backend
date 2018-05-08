defmodule LoggerGraylogBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_graylog_backend,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "LoggerGraylogBackend",
      source_url: "https://github.com/esl/logger_graylog_backend",
      docs: docs(),
      preferred_cli_env: preferred_cli_env()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.18", only: :docs, runtime: false},
      {:dialyxir, "~> 0.5", only: :test, runtime: false},
      {:jason, "~> 1.0"},
      {:optium, "~> 0.3"},
      {:backoff, "~> 1.1"}
    ]
  end

  defp docs do
    [
      main: "README",
      extras: [
        "README.md"
      ]
    ]
  end

  defp preferred_cli_env() do
    [
      docs: :docs,
      dialyzer: :test
    ]
  end
end
