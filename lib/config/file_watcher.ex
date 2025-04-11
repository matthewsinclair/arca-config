defmodule Arca.Config.FileWatcher do
  @moduledoc """
  Watches the configuration file for changes and triggers reloads.

  This module monitors the configuration file for changes made outside
  of the application and ensures the in-memory configuration stays in sync
  with the file on disk. It also prevents notification loops from
  changes made by the application itself.

  IMPORTANT: The FileWatcher no longer automatically creates config files during
  startup. Files are only created when explicitly needed for write operations.
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

  IMPORTANT: This is now only called when explicitly needed, not during startup.

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

    # Check if initialization is complete before creating directories
    initializer_ready = initialization_complete?()

    # Only create directories/files if explicitly requested AND initialization is complete
    if create_if_missing && initializer_ready do
      with :ok <- ensure_directory_exists(config_dir),
           :ok <- ensure_file_exists(config_file, initial_config) do
        :ok
      end
    else
      # Skip file creation if not requested or during startup
      :ok
    end
  end

  # Check if the initializer is ready
  defp initialization_complete? do
    # First check our own state - if we've been notified of completion
    if Process.get(:file_watcher_initialized, false) do
      true
    else
      # Otherwise check the initializer directly
      initializer_available? = Process.whereis(Arca.Config.Initializer) != nil

      if initializer_available? do
        try do
          is_initialized = Arca.Config.Initializer.initialized?()
          # Cache the result if it's true to avoid future calls
          if is_initialized do
            Process.put(:file_watcher_initialized, true)
          end

          is_initialized
        rescue
          # If we can't check, assume it's not complete to be safe
          _ -> false
        end
      else
        # If initializer isn't available, assume true for backward compatibility
        # but only in production - be conservative in dev/test
        Mix.env() == :prod
      end
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # No longer ensure config directory and file exist on startup
    # Instead, get the config file path without creating anything
    config_file = Arca.Config.Cfg.config_file()
    file_info = if File.exists?(config_file), do: get_file_info(config_file), else: nil

    # Schedule first check
    schedule_check()

    {:ok, %{config_file: config_file, last_info: file_info, write_token: nil, initialized: false}}
  end

  @impl true
  def handle_info({:initialization_complete, _pid}, state) do
    # Initialization is now complete, update our state
    # Also store in process dictionary for use in helper functions
    Process.put(:file_watcher_initialized, true)
    {:noreply, %{state | initialized: true}}
  end

  @impl true
  def handle_info(
        :check_file,
        %{config_file: _path, last_info: last_info, write_token: token, initialized: initialized} =
          state
      ) do
    # Always refresh the config path in case it changed due to environment changes
    updated_path = Arca.Config.Cfg.config_file() |> Path.expand()

    # Only check for file changes if the file exists AND either:
    # 1. We are fully initialized, OR
    # 2. This is a self-triggered change (token matches)
    current_info = if File.exists?(updated_path), do: get_file_info(updated_path), else: nil
    token_matches = current_info != nil && token == current_info.mtime

    if File.exists?(updated_path) && (initialized || token_matches) do
      # Check if file has been modified (and not by us)
      if file_changed?(current_info, last_info) do
        if token != current_info.mtime do
          # Reload config quietly, only log errors
          {:ok, _config} = Arca.Config.Server.reload()

          # Notify external callbacks after reload
          Arca.Config.Server.notify_external_change()
          # else
          #   Logger.debug("Config file #{path} changed by our own write, skipping notification")
        end
      end

      # Update state with latest file info and path
      new_state = %{state | last_info: current_info, config_file: updated_path}
      # Schedule next check
      schedule_check()
      {:noreply, new_state}
    else
      # File doesn't exist or we're not initialized yet - just schedule the next check
      schedule_check()
      {:noreply, state}
    end
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
