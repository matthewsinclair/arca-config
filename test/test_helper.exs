# Support functions for CLI test cases
defmodule Arca.Config.Test.Support do
  # Example config file
  @example_config_json_as_map %{
    "database" => %{
      "host" => "localhost"
    },
    "id" => "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
  }

  # Write a known config file to a known location
  def write_default_config_file(config_file, config_path) do
    config_file
    |> Path.expand(config_path)
    |> File.write(Jason.encode!(@example_config_json_as_map, pretty: true))
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

ExUnit.start()
