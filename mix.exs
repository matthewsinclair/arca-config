defmodule ArcaConfig.MixProject do
  use Mix.Project

  def project do
    [
      app: :arca_config,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Arca.Config, path: "_build/escript/arca_config", name: "arca_config"],
      mix_tasks: [
        arca_cli: Mix.Tasks.Arca.Config,
        comment: "🛠️ Arca Config"
      ]
    ]
  end

  def application do
    [
      mod: {Arca.Config, []},
      ansi_enabled: true
    ]
  end

  defp deps do
    [
      {:ok, "~> 2.3"},
      {:httpoison, "~> 2.1"},
      # {:optimus, "~> 0.5.0"},
      {:optimus, github: "matthewsinclair/arca-optimus", branch: "main", override: true},
      {:castore, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:tesla, "~> 1.15"},
      {:certifi, "~> 2.9"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:owl, "~> 0.12"},
      {:ucwidth, "~> 0.2"},
      {:pathex, "~> 2.6"},
      {:table_rex, "~> 4.1"},
      {:elixir_uuid, "~> 1.2"},
      {:meck, "~> 1.0", only: :test},
      {:dotenv, "~> 3.0", only: [:dev, :test], runtime: false}
    ]
  end
end
