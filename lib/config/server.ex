defmodule Arca.Config.Server do
  @moduledoc """
  GenServer that manages the configuration state.

  This server is responsible for:
  1. Loading configuration from files
  2. Maintaining in-memory state of configuration
  3. Coordinating cache updates
  4. Notifying subscribers of configuration changes
  5. Persisting configuration changes to disk
  """

  use GenServer

  alias Arca.Config.Cache
  alias Arca.Config.Cfg, as: LegacyCfg

  # Client API

  @doc """
  Starts the configuration server.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Gets a configuration value by key path.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, value}` if the key exists
    - `{:error, reason}` if the key doesn't exist or another error occurs
  """
  @spec get(String.t() | atom() | list()) :: {:ok, any()} | {:error, term()}
  def get(key) do
    key_path = normalize_key_path(key)
    normal_get(key_path)
  end

  # Standard get operation
  defp normal_get(key_path) do
    # Try to get from cache first
    case Cache.get(key_path) do
      {:ok, value} ->
        {:ok, value}

      {:error, :not_found} ->
        # Not in cache, try to get from disk and update cache if found
        case GenServer.call(__MODULE__, {:get, key_path}) do
          {:ok, value} = result ->
            # Update cache with the value
            Cache.put(key_path, value)
            result

          error ->
            error
        end
    end
  end

  @doc """
  Gets a configuration value by key path or raises an error if not found.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - The configuration value if the key exists

  ## Raises
    - `RuntimeError` if the key doesn't exist or another error occurs
  """
  @spec get!(String.t() | atom() | list()) :: any() | no_return()
  def get!(key) do
    case get(key) do
      {:ok, value} -> value
      {:error, reason} -> raise RuntimeError, message: "Configuration error: #{reason}"
    end
  end

  @doc """
  Updates a configuration value.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])
    - `value`: The new value to set

  ## Returns
    - `{:ok, value}` if the update was successful
    - `{:error, reason}` if an error occurred
  """
  @spec put(String.t() | atom() | list(), any()) :: {:ok, any()} | {:error, term()}
  def put(key, value) do
    key_path = normalize_key_path(key)
    GenServer.call(__MODULE__, {:put, key_path, value})
  end

  @doc """
  Updates a configuration value or raises an error if the operation fails.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])
    - `value`: The new value to set

  ## Returns
    - The value if the update was successful

  ## Raises
    - `RuntimeError` if an error occurred
  """
  @spec put!(String.t() | atom() | list(), any()) :: any() | no_return()
  def put!(key, value) do
    case put(key, value) do
      {:ok, result} -> result
      {:error, reason} -> raise RuntimeError, message: "Configuration error: #{reason}"
    end
  end

  @doc """
  Deletes a configuration key and its value.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :deleted}` if the deletion was successful
    - `{:error, reason}` if an error occurred
  """
  @spec delete(String.t() | atom() | list()) :: {:ok, :deleted} | {:error, term()}
  def delete(key) do
    key_path = normalize_key_path(key)
    GenServer.call(__MODULE__, {:delete, key_path})
  end

  @doc """
  Deletes a configuration key and its value or raises an error if the operation fails.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `:deleted` if the deletion was successful

  ## Raises
    - `RuntimeError` if an error occurred
  """
  @spec delete!(String.t() | atom() | list()) :: :deleted | no_return()
  def delete!(key) do
    case delete(key) do
      {:ok, result} -> result
      {:error, reason} -> raise RuntimeError, message: "Configuration error: #{reason}"
    end
  end

  @doc """
  Reloads the configuration from disk.

  ## Returns
    - `{:ok, config}` with the loaded configuration if successful
    - `{:error, reason}` if an error occurred
  """
  @spec reload() :: {:ok, map()} | {:error, term()}
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Subscribes to changes to a specific configuration key.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :subscribed}` if the subscription was successful
  """
  @spec subscribe(String.t() | atom() | list()) :: {:ok, :subscribed}
  def subscribe(key) do
    key_path = normalize_key_path(key)
    Registry.register(Arca.Config.Registry, key_path, nil)
    {:ok, :subscribed}
  end

  @doc """
  Unsubscribes from changes to a specific configuration key.

  ## Parameters
    - `key`: A dot-separated string or atom path (e.g., "database.host" or [:database, :host])

  ## Returns
    - `{:ok, :unsubscribed}` if the unsubscription was successful
  """
  @spec unsubscribe(String.t() | atom() | list()) :: {:ok, :unsubscribed}
  def unsubscribe(key) do
    key_path = normalize_key_path(key)
    Registry.unregister(Arca.Config.Registry, key_path)
    {:ok, :unsubscribed}
  end

  @doc """
  Registers a callback function to be called when the configuration changes externally.

  ## Parameters
    - `callback_id`: An identifier for the callback (used for unregistering)
    - `callback_fn`: A function that takes a map of the entire config as its argument

  ## Returns
    - `{:ok, :registered}` if the registration was successful
  """
  @spec register_change_callback(term(), (map() -> any())) :: {:ok, :registered}
  def register_change_callback(callback_id, callback_fn) when is_function(callback_fn, 1) do
    Registry.register(Arca.Config.CallbackRegistry, :config_change, {callback_id, callback_fn})
    {:ok, :registered}
  end

  @doc """
  Unregisters a previously registered callback function.

  ## Parameters
    - `callback_id`: The identifier of the callback to unregister

  ## Returns
    - `{:ok, :unregistered}` if the unregistration was successful
  """
  @spec unregister_change_callback(term()) :: {:ok, :unregistered}
  def unregister_change_callback(callback_id) do
    Registry.unregister_match(Arca.Config.CallbackRegistry, :config_change, {callback_id, :_})
    {:ok, :unregistered}
  end

  @doc """
  Adds a callback function to be called whenever the configuration changes.
  Unlike `register_change_callback/2`, this callback does not receive any arguments.

  ## Parameters
    - `callback_fn`: A 0-arity function to execute when config changes

  ## Returns
    - `{:ok, reference}` if the registration was successful, where reference is used to remove the callback
  """
  @spec add_callback(function()) :: {:ok, reference()}
  def add_callback(callback_fn) when is_function(callback_fn, 0) do
    # Generate a unique reference to identify this callback
    callback_ref = make_ref()

    # Register the callback with the registry
    Registry.register(
      Arca.Config.SimpleCallbackRegistry,
      :simple_callback,
      {callback_ref, callback_fn}
    )

    # Return the reference for later removal
    {:ok, callback_ref}
  end

  @doc """
  Removes a previously registered callback function.

  ## Parameters
    - `callback_ref`: The reference returned by `add_callback/1`

  ## Returns
    - `{:ok, :removed}` if the callback was successfully removed
    - `{:error, :not_found}` if the callback wasn't registered
  """
  @spec remove_callback(reference()) :: {:ok, :removed} | {:error, :not_found}
  def remove_callback(callback_ref) do
    # Find the exact pid and value for the callback to unregister
    case Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
         |> Enum.find(fn {_pid, {ref, _fn}} -> ref == callback_ref end) do
      nil ->
        {:error, :not_found}

      {_pid, _value} ->
        # Unregister the specific pid/value pair
        Registry.unregister_match(
          Arca.Config.SimpleCallbackRegistry,
          :simple_callback,
          {callback_ref, :_}
        )

        {:ok, :removed}
    end
  end

  @doc """
  Notifies all registered 0-arity callbacks.
  This is called automatically whenever the configuration changes.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been executed
  """
  @spec notify_callbacks() :: {:ok, :notified}
  def notify_callbacks do
    require Logger

    # Get number of callbacks for logging
    # registry_entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
    # Logger.debug("Notifying #{length(registry_entries)} simple callbacks")

    # Execute all registered callbacks
    Registry.dispatch(Arca.Config.SimpleCallbackRegistry, :simple_callback, fn entries ->
      for {_pid, {ref, callback_fn}} <- entries do
        try do
          callback_fn.()
        rescue
          e ->
            Logger.error("Simple callback error for #{inspect(ref)}: #{inspect(e)}")
        end
      end
    end)

    {:ok, :notified}
  end

  @doc """
  Loads configuration during the :load_config start phase.
  This should be called by the parent application during its start phase.

  ## Returns
    - `{:ok, config}` if configuration was loaded successfully
    - `{:error, reason}` if there was an error loading configuration
  """
  @spec load_config() :: {:ok, map()} | {:error, term()}
  def load_config do
    GenServer.call(__MODULE__, :load_config)
  end

  @doc """
  Switches the configuration file location at runtime.

  ## Parameters
    - `opts`: Keyword list with optional `:path` and `:file` keys

  ## Returns
    - `{:ok, previous_location}` with the previous path and file settings
    - `{:error, reason}` if an error occurred
  """
  @spec switch_config_location(keyword()) :: {:ok, keyword()} | {:error, term()}
  def switch_config_location(opts \\ []) do
    GenServer.call(__MODULE__, {:switch_config_location, opts})
  end

  @doc """
  Notifies all registered callback functions of an external configuration change.
  This is called by the FileWatcher when it detects changes to the config file.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been notified
  """
  @spec notify_external_change() :: {:ok, :notified}
  def notify_external_change do
    # Get current config snapshot
    config =
      case GenServer.call(__MODULE__, :get_config) do
        {:ok, conf} -> conf
        conf when is_map(conf) -> conf
      end

    # Silently dispatch notifications
    require Logger

    # Notify all registered callbacks with current config
    Registry.dispatch(Arca.Config.CallbackRegistry, :config_change, fn entries ->
      for {_process_pid, {id, callback_fn}} <- entries do
        # Execute callback in the process that requested it
        try do
          callback_fn.(config)
        rescue
          e ->
            Logger.error("Config change callback error: #{inspect(id)}: #{inspect(e)}")
        end
      end
    end)

    # Also notify 0-arity callbacks
    notify_callbacks()

    {:ok, :notified}
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Start with empty configuration - configuration will be loaded during start phase
    {:ok, %{config: %{}, loaded: false}}
  end

  @impl true
  def handle_info({:notify_paths, paths_to_notify}, state) do
    # Process each path for notification
    Enum.each(paths_to_notify, fn {path, value} ->
      # Use Registry directly to notify subscribers
      Registry.dispatch(Arca.Config.Registry, path, fn entries ->
        for {pid, _} <- entries do
          send(pid, {:config_updated, path, value})
        end
      end)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:load_config, _from, state) do
    # Load initial configuration
    case LegacyCfg.load() do
      {:ok, config} ->
        # Initialize cache with loaded config
        Cache.clear()
        build_cache(config)

        {:reply, {:ok, config}, %{state | config: config, loaded: true}}

      {:error, _reason} = error ->
        # Initialize with empty config on error but still mark as loaded
        Cache.clear()
        build_cache(%{})

        {:reply, error, %{state | config: %{}, loaded: true}}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:reset_for_test, new_config}, _from, _state) do
    # Reset server state for testing
    {:reply, :ok, %{config: new_config, loaded: false}}
  end

  @impl true
  def handle_call({:get, key_path}, _from, state) do
    # If config hasn't been loaded yet, load it on-demand
    state_to_use =
      if map_size(state.config) == 0 and not state.loaded do
        case LegacyCfg.load() do
          {:ok, config} ->
            Cache.clear()
            build_cache(config)
            %{state | config: config, loaded: true}

          {:error, _} ->
            # If loading fails, mark as loaded but keep empty config
            %{state | loaded: true}
        end
      else
        state
      end

    result = get_in_nested(state_to_use.config, key_path)
    {:reply, result, state_to_use}
  end

  @impl true
  def handle_call({:put, key_path, value}, _from, state) do
    # Read current config from file to ensure we have the latest version
    current_config = read_current_config(state.config)

    # Update in-memory config (merging with current config from file)
    new_config = put_in_nested(current_config, key_path, value)

    # Write to file
    write_config(new_config)

    # Update cache
    Cache.put(key_path, value)

    # Get all paths that need notification (self and ancestors)
    paths_to_notify = get_notification_paths(key_path, new_config)

    # Send process message to handle notifications asynchronously
    Process.send(self(), {:notify_paths, paths_to_notify}, [:noconnect])

    # Notify all callbacks of the change
    notify_callbacks()

    # Return success
    {:reply, {:ok, value}, %{state | config: new_config}}
  end

  @impl true
  def handle_call({:delete, key_path}, _from, state) do
    # Read current config from file to ensure we have the latest version
    current_config = read_current_config(state.config)

    # Delete the key path from config
    new_config = delete_in_nested(current_config, key_path)

    # Write to file
    write_config(new_config)

    # Invalidate cache
    Cache.invalidate(key_path)

    # Get all paths that need notification (self and ancestors)
    paths_to_notify = get_notification_paths(key_path, current_config)

    # Send process message to handle notifications asynchronously
    Process.send(self(), {:notify_paths, paths_to_notify}, [:noconnect])

    # Notify all callbacks of the change
    notify_callbacks()

    # Return success
    {:reply, {:ok, :deleted}, %{state | config: new_config}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    case LegacyCfg.load() do
      {:ok, config} ->
        # Clear and rebuild cache
        Cache.clear()
        build_cache(config)

        # Notify all callbacks of the change
        notify_callbacks()

        # Return success
        {:reply, {:ok, config}, %{state | config: config}}

      {:error, reason} = error ->
        {:reply, error, Map.put(state, :load_error, reason)}
    end
  end

  @impl true
  def handle_call({:switch_config_location, opts}, _from, state) do
    # Get the env var prefix
    env_prefix = LegacyCfg.env_var_prefix()
    path_var = "#{env_prefix}_CONFIG_PATH"
    file_var = "#{env_prefix}_CONFIG_FILE"

    # Store current location
    previous_location = [
      path: System.get_env(path_var),
      file: System.get_env(file_var)
    ]

    # Stop the current file watcher
    Arca.Config.FileWatcher.stop_watching()

    # Update environment variables if options provided
    if Keyword.has_key?(opts, :path) do
      case Keyword.get(opts, :path) do
        nil -> System.delete_env(path_var)
        path -> System.put_env(path_var, path)
      end
    end

    if Keyword.has_key?(opts, :file) do
      case Keyword.get(opts, :file) do
        nil -> System.delete_env(file_var)
        file -> System.put_env(file_var, file)
      end
    end

    # Clear the cache
    Cache.clear()

    # Load configuration from new location
    case LegacyCfg.load() do
      {:ok, config} ->
        # Rebuild cache with new config
        build_cache(config)

        # Restart file watcher with new location
        Arca.Config.FileWatcher.start_watching()

        # Notify all callbacks of the change
        notify_callbacks()

        # Return previous location for restoration
        {:reply, {:ok, previous_location}, %{state | config: config, loaded: true}}

      {:error, reason} ->
        # On error, restore previous environment variables
        if previous_location[:path] do
          System.put_env(path_var, previous_location[:path])
        else
          System.delete_env(path_var)
        end

        if previous_location[:file] do
          System.put_env(file_var, previous_location[:file])
        else
          System.delete_env(file_var)
        end

        # Restart file watcher with original location
        Arca.Config.FileWatcher.start_watching()

        {:reply, {:error, reason}, state}
    end
  end

  # Read the current configuration from file or fall back to provided config
  defp read_current_config(fallback_config) do
    require Logger

    # Use the fixed Arca.Config.Cfg.config_file() function which properly expands paths
    config_path = Arca.Config.Cfg.config_file() |> Path.expand()

    # Logger.debug("Reading config from path: #{config_path}")

    with {:ok, content} <- File.read(config_path),
         {:ok, config} <- Jason.decode(content) do
      config
    else
      _error ->
        # Logger.debug("Error reading config file: #{inspect(error)}, using fallback config")
        fallback_config
    end
  end

  # Private functions

  defp normalize_key_path(key) when is_list(key), do: key

  defp normalize_key_path(key) do
    key
    |> to_string()
    |> String.split(".")
  end

  # Base case: reached leaf value successfully
  defp get_in_nested(result, []), do: {:ok, result}

  # Error case: current position is not a map but we need to go deeper
  defp get_in_nested(current, [_head | _tail]) when not is_map(current),
    do: {:error, "Key not found"}

  # Recursive case: get value at current key and continue
  defp get_in_nested(config, [head | tail]) do
    case Map.get(config, head) do
      nil -> {:error, "Key not found"}
      value -> get_in_nested(value, tail)
    end
  end

  # Base case: leaf key - directly update the map
  defp put_in_nested(config, [last_key], value) do
    Map.put(config, last_key, value)
  end

  # Recursive case: need to traverse deeper
  defp put_in_nested(config, [head | tail], value) do
    current_value = get_map_value(config, head)
    updated_value = put_in_nested(current_value, tail, value)

    Map.put(config, head, updated_value)
  end

  # Helper to ensure we're working with a map for nested operations
  defp get_map_value(config, key) do
    case Map.get(config, key) do
      nil -> %{}
      val when is_map(val) -> val
      _non_map -> %{}
    end
  end

  # Base case: leaf key - delete the key from map
  defp delete_in_nested(config, [last_key]) do
    Map.delete(config, last_key)
  end

  # Recursive case: need to traverse deeper
  defp delete_in_nested(config, [head | tail]) do
    case Map.get(config, head) do
      nil ->
        # If key doesn't exist, return config unchanged
        config

      submap when is_map(submap) ->
        # Go deeper
        updated_submap = delete_in_nested(submap, tail)

        # If map is empty after deletion, remove it too
        if map_size(updated_submap) == 0 do
          Map.delete(config, head)
        else
          Map.put(config, head, updated_submap)
        end

      _non_map ->
        # If value at key is not a map, can't traverse further, return unchanged
        config
    end
  end

  # Write configuration to the current config file
  defp write_config(config) do
    require Logger

    # Always get a fresh config file path to ensure we have the latest environment settings
    # This is critical when environment variables change during runtime
    config_path = Arca.Config.Cfg.config_file()

    # Extract directory from the full path
    # IMPORTANT: Always fully expand paths to prevent recursive directory creation issues
    # Path.expand converts paths like "./.config/" or "/abs/path" to their absolute form
    expanded_config_path = Path.expand(config_path)

    # No logging during normal operation

    # Register a unique write token to avoid self-notifications
    token = System.monotonic_time()
    Arca.Config.FileWatcher.register_write(token)

    # Encode configuration
    encoded_config = Jason.encode!(config, pretty: true)

    # Ensure parent directory exists and file exists before writing
    # This now explicitly creates the directory/file only when needed for writing
    Arca.Config.FileWatcher.ensure_config_exists(config, true)

    # Write to the absolute path
    write_file_with_logging(expanded_config_path, encoded_config)
  end

  # Write to file with error logging
  defp write_file_with_logging(path, content) do
    case File.write(path, content) do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Failed to write config file: #{inspect(reason)}")
    end
  end

  defp build_cache(config) do
    flatten_and_cache(config)
  end

  defp flatten_and_cache(config, prefix \\ []) do
    if is_map(config) do
      # Cache this level
      if prefix != [] do
        Cache.put(prefix, config)
      end

      # Recursively cache all nested values
      Enum.each(config, fn {key, value} ->
        new_prefix = prefix ++ [key]
        Cache.put(new_prefix, value)

        if is_map(value) do
          flatten_and_cache(value, new_prefix)
        end
      end)
    end
  end

  # Get all paths that need notification (self and ancestors)
  defp get_notification_paths(key_path, config) do
    get_notification_paths(key_path, config, [])
  end

  # Single-key path (no parents to add)
  defp get_notification_paths([_] = key_path, config, paths) do
    add_path_if_exists(key_path, config, paths)
  end

  # Multi-level path (need to check for parents)
  defp get_notification_paths(key_path, config, paths) do
    # First add the current path
    updated_paths = add_path_if_exists(key_path, config, paths)

    # Then add the parent path
    parent_path = Enum.slice(key_path, 0, length(key_path) - 1)
    get_notification_paths(parent_path, config, updated_paths)
  end

  # Add a path to the accumulated list if it exists in the config
  defp add_path_if_exists(key_path, config, paths) do
    case get_in_nested(config, key_path) do
      {:ok, value} -> [{key_path, value} | paths]
      _ -> paths
    end
  end
end
