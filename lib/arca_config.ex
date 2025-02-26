defmodule Arca.Config do
  @moduledoc """
  Arca.Config provides a simple file-based configuration utility for Elixir projects.
  
  It allows reading from and writing to a JSON configuration file, with support for
  nested properties using dot notation.
  """

  use Application
  alias Arca.Config.Cfg

  @doc """
  Handle Application functionality to start the Arca.Config subsystem.
  """
  @impl true
  def start(_type, _args) do
    {:ok, self()}
  end

  @doc """
  Entry point for the CLI.
  
  Parses command-line arguments and executes the appropriate action.
  """
  @spec main(list(String.t())) :: :ok
  def main(argv) do
    case argv do
      ["set", key | rest] ->
        # Combine all remaining arguments into a single value
        value = Enum.join(rest, " ")
        handle_set(key, value)
      
      ["get", key | _] ->
        handle_get(key)
        
      ["list" | _] ->
        handle_list()
        
      _ ->
        cli_spec()
        |> Optimus.parse!(argv)
        |> process_command()
    end
  end

  defp cli_spec do
    Optimus.new!(
      name: Application.get_env(:arca_config, :name, "arca_config"),
      description: Application.get_env(:arca_config, :description, "A simple file-based configurator for Elixir apps"),
      version: Application.get_env(:arca_config, :version, "0.1.0"),
      author: Application.get_env(:arca_config, :author, "Arca"),
      about: Application.get_env(:arca_config, :about, "Arca Config CLI"),
      allow_unknown_args: true,
      parse_double_dash: true,
      subcommands: [
        get: [
          name: "get",
          about: "Get a configuration value",
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to get (e.g., 'database.host')",
              required: true
            ]
          ]
        ],
        set: [
          name: "set",
          about: "Set a configuration value",
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to set (e.g., 'database.host')",
              required: true
            ],
            value: [
              value_name: "VALUE",
              help: "The value to set",
              required: true
            ]
          ]
        ],
        list: [
          name: "list",
          about: "List all configuration values"
        ]
      ]
    )
  end

  defp process_command({[:list], _parse_result}) do
    handle_list()
  end

  defp process_command({[:get], %{args: %{key: key}}}) do
    handle_get(key)
  end

  defp process_command({[:set], %{args: %{key: key, value: value}}}) do
    handle_set(key, value)
  end

  defp process_command(_) do
    IO.puts("Invalid command. Use --help for usage information.")
    :ok
  end

  defp handle_get(key) do
    case Cfg.get(key) do
      {:ok, value} ->
        if is_map(value) do
          IO.puts(Jason.encode!(value, pretty: true))
        else
          IO.puts(value)
        end

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp handle_set(key, value) do
    # Try to convert string to appropriate type
    value = try_convert_value(value)

    case Cfg.put(key, value) do
      {:ok, _} ->
        IO.puts("Successfully set '#{key}' to '#{value}'")

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp handle_list do
    case Cfg.load() do
      {:ok, config} ->
        IO.puts(Jason.encode!(config, pretty: true))

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp try_convert_value(value) do
    cond do
      value == "true" -> true
      value == "false" -> false
      Regex.match?(~r/^-?\d+$/, value) -> String.to_integer(value)
      Regex.match?(~r/^-?\d+\.\d+$/, value) -> String.to_float(value)
      String.starts_with?(value, "[") and String.ends_with?(value, "]") ->
        case Jason.decode(value) do
          {:ok, decoded} -> decoded
          _ -> value
        end
      String.starts_with?(value, "{") and String.ends_with?(value, "}") ->
        case Jason.decode(value) do
          {:ok, decoded} -> decoded
          _ -> value
        end
      true -> value
    end
  end
end
