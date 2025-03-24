defmodule Arca.Config.FileWatcher do
  @moduledoc """
  Watches the configuration file for changes and triggers reloads.

  This module monitors the configuration file for changes made outside
  of the application and ensures the in-memory configuration stays in sync
  with the file on disk. It also prevents notification loops from
  changes made by the application itself.
  """

  use GenServer
  require Logger

  # 5 seconds
  @check_interval 5_000

  @doc """
  Starts the file watcher process.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Registers a write operation to avoid self-notification.

  When the application writes to the config file, it should register
  the write with a unique token so the file watcher can ignore those
  changes and avoid notification loops.

  ## Parameters
    - `token`: A unique token identifying the write operation
  """
  def register_write(token) do
    GenServer.cast(__MODULE__, {:register_write, token})
  end

  @doc """
  Ensures the configuration directory and file exist.

  This function creates the config directory if it doesn't exist
  and creates an empty config file if one doesn't exist yet.

  ## Parameters
    - `initial_config`: Optional map with default configuration values (defaults to empty map)

  ## Returns
    - `:ok` if the directory and file were created successfully
    - `{:error, reason}` if an error occurred
  """
  @spec ensure_config_exists(map()) :: :ok | {:error, term()}
  def ensure_config_exists(initial_config \\ %{}) do
    # Use Arca.Config.Cfg.config_file() which now properly expands paths
    config_file = Arca.Config.Cfg.config_file() |> Path.expand()
    config_dir = Path.dirname(config_file)

    with :ok <- ensure_directory_exists(config_dir),
         :ok <- ensure_file_exists(config_file, initial_config) do
      :ok
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Ensure config directory and file exist
    case ensure_config_exists() do
      :ok ->
        # Get initial file info
        config_file = Arca.Config.Cfg.config_file()
        file_info = get_file_info(config_file)

        # Schedule first check
        schedule_check()

        {:ok, %{config_file: config_file, last_info: file_info, write_token: nil}}

      {:error, reason} ->
        Logger.error("Failed to ensure config exists: #{reason}")
        # Continue with what we can
        config_file = Arca.Config.Cfg.config_file()
        {:ok, %{config_file: config_file, last_info: nil, write_token: nil}}
    end
  end

  @impl true
  def handle_info(
        :check_file,
        %{config_file: path, last_info: last_info, write_token: token} = state
      ) do
    current_info = get_file_info(path)

    # Check if file has been modified (and not by us)
    if file_changed?(current_info, last_info) do
      if token != current_info.mtime do
        # Reload config
        Logger.info("Config file #{path} changed, reloading")
        {:ok, _config} = Arca.Config.Server.reload()

        # Notify external callbacks after reload
        Arca.Config.Server.notify_external_change()
      else
        Logger.debug("Config file #{path} changed by our own write, skipping notification")
      end
    end

    # Schedule next check
    schedule_check()

    {:noreply, %{state | last_info: current_info}}
  end

  @impl true
  def handle_cast({:register_write, token}, state) do
    # Register that we've written to the file (to avoid self-notification)
    {:noreply, %{state | write_token: token}}
  end

  # Private functions

  defp schedule_check do
    Process.send_after(self(), :check_file, @check_interval)
  end

  defp get_file_info(path) do
    case File.stat(path) do
      {:ok, info} -> info
      _ -> nil
    end
  end

  defp file_changed?(nil, _), do: false
  defp file_changed?(_, nil), do: true

  defp file_changed?(current, last) do
    current.mtime != last.mtime || current.size != last.size
  end

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
