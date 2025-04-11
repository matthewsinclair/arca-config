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

    # Check if initialization is complete
    initializer_available? =
      try do
        # Check if the initializer module/process exists
        Process.whereis(Arca.Config.Initializer) != nil
      rescue
        _ -> false
      end

    if initializer_available? do
      # Only check if initialization is complete if the initializer is available
      initialization_complete? =
        try do
          Arca.Config.Initializer.initialized?()
        rescue
          # If we can't check, assume it's not complete to be safe
          _ -> false
        end

      # If we're still initializing, provide conservative defaults
      if !initialization_complete? do
        case Cache.get(key_path) do
          {:ok, value} ->
            {:ok, value}

          _ ->
            # During initialization, return empty values rather than triggering more lookups
            # This prevents circular dependencies during startup
            default_value_for_type(key_path)
        end
      else
        # Normal path for initialized system
        normal_get(key_path)
      end
    else
      # Fallback for backward compatibility or if initializer isn't available
      normal_get(key_path)
    end
  end

  # Standard get operation when fully initialized
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

  # Return conservative defaults based on key name patterns
  defp default_value_for_type(key_path) do
    key_str = Enum.join(key_path, ".")

    cond do
      # Return empty maps for common container types
      String.contains?(key_str, "config") -> {:ok, %{}}
      String.contains?(key_str, "settings") -> {:ok, %{}}
      String.contains?(key_str, "options") -> {:ok, %{}}
      # Return empty list for collection types
      String.contains?(key_str, "list") -> {:ok, []}
      String.contains?(key_str, "items") -> {:ok, []}
      # Return empty string for common string types
      String.contains?(key_str, "name") -> {:ok, ""}
      String.contains?(key_str, "path") -> {:ok, ""}
      String.contains?(key_str, "file") -> {:ok, ""}
      # Return false for boolean types
      String.contains?(key_str, "enabled") -> {:ok, false}
      String.contains?(key_str, "active") -> {:ok, false}
      # Default empty value
      true -> {:ok, nil}
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
    # Start with empty configuration - the Initializer will load it properly
    # Don't cache the config_file path in the state anymore - always get fresh path
    {:ok, %{config: %{}, initializing: false}}
  end

  # Keep the initialize_config handler for backwards compatibility
  # but delegate to the Initializer instead of doing work here
  @impl true
  def handle_info(:initialize_config, state) do
    # This is now handled by Arca.Config.Initializer
    # No-op to maintain backward compatibility
    {:noreply, state}
  end

  @impl true
  def handle_info({:initialization_complete, _pid}, state) do
    # Initialization is now complete
    {:noreply, state}
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
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:get, key_path}, _from, state) do
    result = get_in_nested(state.config, key_path)
    {:reply, result, state}
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
