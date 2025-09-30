defmodule Arca.Config.FileWatcher do
  @moduledoc """
  Watches the configuration file for changes and triggers reloads.

  This module monitors the configuration file for changes made outside
  of the application and ensures the in-memory configuration stays in sync
  with the file on disk. It also prevents notification loops from
  changes made by the application itself.

  The FileWatcher starts in dormant state and only begins monitoring after
  configuration is loaded during the start phase.
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
  Starts file watching after configuration has been loaded.
  This should be called after the configuration is loaded during the start phase.

  ## Parameters
    - `config_file`: Optional specific config file path to watch. If not provided,
      uses the path from `Arca.Config.Cfg.config_file/0`

  ## Returns
    - `:ok` if file watching was started successfully
  """
  @spec start_watching(String.t() | nil) :: :ok
  def start_watching(config_file \\ nil) do
    GenServer.cast(__MODULE__, {:start_watching, config_file})
  end

  @doc """
  Stops file watching.

  This function stops the FileWatcher from monitoring the configuration file.
  It can be called when switching configuration locations or during shutdown.

  ## Returns
    - `:ok` when file watching has been stopped
  """
  @spec stop_watching() :: :ok
  def stop_watching do
    GenServer.call(__MODULE__, :stop_watching)
  end

  @doc """
  Ensures the configuration directory and file exist.

  This function creates the config directory if it doesn't exist
  and creates an empty config file if one doesn't exist yet.

  ## Parameters
    - `initial_config`: Optional map with default configuration values (defaults to empty map)
    - `create_if_missing`: Whether to create the directory and file if missing (defaults to true)

  ## Returns
    - `:ok` if the directory and file were created successfully or if creation was skipped
    - `{:error, reason}` if an error occurred
  """
  @spec ensure_config_exists(map(), boolean()) :: :ok | {:error, term()}
  def ensure_config_exists(initial_config \\ %{}, create_if_missing \\ true) do
    # Use Arca.Config.Cfg.config_file() which now properly expands paths
    config_file = Arca.Config.Cfg.config_file() |> Path.expand()
    config_dir = Path.dirname(config_file)

    # Only create directories/files if explicitly requested
    if create_if_missing do
      with :ok <- ensure_directory_exists(config_dir),
           :ok <- ensure_file_exists(config_file, initial_config) do
        :ok
      end
    else
      # Skip file creation if not requested
      :ok
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Start in dormant state - no file checking until configuration is loaded
    {:ok,
     %{config_file: nil, last_info: nil, write_token: nil, watching: false, check_timer: nil}}
  end

  @impl true
  def handle_cast({:start_watching, config_file}, state) do
    # Configuration has been loaded, start watching
    file_to_watch = config_file || Arca.Config.Cfg.config_file()
    file_info = if File.exists?(file_to_watch), do: get_file_info(file_to_watch), else: nil

    # Cancel any existing timer
    if state[:check_timer] do
      Process.cancel_timer(state.check_timer)
    end

    # Schedule first check
    timer = schedule_check()

    {:noreply,
     %{
       state
       | config_file: file_to_watch,
         last_info: file_info,
         watching: true,
         check_timer: timer
     }}
  end

  # Legacy compatibility - handle old :start_watching atom
  @impl true
  def handle_cast(:start_watching, state) do
    handle_cast({:start_watching, nil}, state)
  end

  @impl true
  def handle_cast({:register_write, token}, state) do
    # Register that we've written to the file (to avoid self-notification)
    {:noreply, %{state | write_token: token}}
  end

  @impl true
  def handle_call(:stop_watching, _from, state) do
    # Cancel any existing timer
    if state[:check_timer] do
      Process.cancel_timer(state.check_timer)
    end

    # Reset to dormant state
    {:reply, :ok,
     %{config_file: nil, last_info: nil, write_token: nil, watching: false, check_timer: nil}}
  end

  @impl true
  def handle_info({:reset_to_dormant, _pid}, _state) do
    # Reset to dormant state for testing
    {:noreply,
     %{config_file: nil, last_info: nil, write_token: nil, watching: false, check_timer: nil}}
  end

  @impl true
  def handle_info(
        :check_file,
        %{config_file: _path, last_info: last_info, write_token: token, watching: watching} =
          state
      ) do
    # Only check for file changes if we are watching
    if watching do
      # Always refresh the config path in case it changed due to environment changes
      updated_path = Arca.Config.Cfg.config_file() |> Path.expand()

      # Only check for file changes if the file exists
      current_info = if File.exists?(updated_path), do: get_file_info(updated_path), else: nil

      if File.exists?(updated_path) do
        # Check if file has been modified (and not by us)
        if file_changed?(current_info, last_info) do
          if token == nil do
            # External change - reload config and notify
            {:ok, _config} = Arca.Config.Server.reload()
            Arca.Config.Server.notify_external_change()
          end
        end

        # Update state with latest file info and path, and clear any registered token
        # Schedule next check and store timer
        timer = schedule_check()

        new_state = %{
          state
          | last_info: current_info,
            config_file: updated_path,
            write_token: nil,
            check_timer: timer
        }

        {:noreply, new_state}
      else
        # File doesn't exist - just schedule the next check
        timer = schedule_check()
        {:noreply, %{state | check_timer: timer}}
      end
    else
      # Not watching yet - just schedule the next check
      timer = schedule_check()
      {:noreply, %{state | check_timer: timer}}
    end
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
