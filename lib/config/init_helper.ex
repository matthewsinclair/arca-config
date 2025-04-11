defmodule Arca.Config.InitHelper do
  @moduledoc """
  Provides helper functions for initializing configuration for applications using Arca.Config.

  This module helps application developers ensure that configuration directories and files
  exist before the Arca.Config system attempts to load them.
  """

  alias Arca.Config.FileWatcher
  alias Arca.Config.Cfg

  @doc """
  Initializes the configuration for an application.

  This function:
  1. Ensures the configuration directory exists
  2. Creates a default configuration file if one doesn't exist
  3. Returns the location of the configuration file

  ## Parameters
    - `app_name`: The name of the application (atom) - will be used to determine config domain
    - `initial_config`: A map containing initial configuration values (default: %{})
    
  ## Returns
    - `{:ok, config_path}` if initialization succeeded
    - `{:error, reason}` if initialization failed
  """
  @spec init_config(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def init_config(app_name, initial_config \\ %{}) do
    # Set the config domain to the app name
    Application.put_env(:arca_config, :config_domain, app_name)

    # Get the config file path that will be used
    config_file = Cfg.config_file() |> Path.expand()

    # Ensure config directory and file exist - force creation since this is explicit
    case FileWatcher.ensure_config_exists(initial_config, true) do
      :ok -> {:ok, config_file}
      error -> error
    end
  end

  @doc """
  Sets up a default configuration directory in the user's home directory.

  This function creates a directory like `~/.app_name/` and ensures
  a config.json file exists within it.

  ## Parameters
    - `app_name`: The name of the application as an atom (e.g., `:my_app`)
    - `initial_config`: A map containing initial configuration values (default: %{})
    
  ## Returns
    - `{:ok, config_path}` if the setup succeeded
    - `{:error, reason}` if the setup failed
  """
  @spec setup_default_config(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def setup_default_config(app_name, initial_config \\ %{}) do
    app_str = to_string(app_name)
    # Use the current directory instead of home directory
    # This keeps all test files contained within the project
    config_dir = Path.join(File.cwd!(), ".#{app_str}")
    config_file = Path.join(config_dir, "config.json")

    # Set environment variables to override defaults
    System.put_env("#{String.upcase(app_str)}_CONFIG_PATH", config_dir)
    System.put_env("#{String.upcase(app_str)}_CONFIG_FILE", "config.json")

    # Set the config domain
    Application.put_env(:arca_config, :config_domain, app_name)

    # Ensure config directory exists
    with :ok <- ensure_directory_exists(config_dir),
         :ok <- ensure_file_exists(config_file, initial_config) do
      {:ok, config_file}
    end
  end

  # Private helpers

  defp ensure_directory_exists(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, reason} -> {:error, "Failed to create config directory: #{reason}"}
    end
  end

  defp ensure_file_exists(file_path, initial_config) do
    if !File.exists?(file_path) do
      content = Jason.encode!(initial_config, pretty: true)

      case File.write(file_path, content) do
        :ok -> :ok
        {:error, reason} -> {:error, "Failed to create config file: #{reason}"}
      end
    else
      :ok
    end
  end
end
