defmodule Mix.Tasks.Arca.Config do
  @moduledoc "Custom mix tasks for Arca Config: mix arca.config"
  use Mix.Task
  alias Arca.Config

  @impl Mix.Task
  @requirements ["app.config", "app.start"]
  @shortdoc "Runs Arca Config"
  @doc "Invokes Arca Config and passes it the supplied command line params."
  def run(args) do
    Config.main(args)
  end
end
