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
  Notifies all registered callback functions of an external configuration change.
  This is called by the FileWatcher when it detects changes to the config file.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been notified
  """
  @spec notify_external_change() :: {:ok, :notified}
  def notify_external_change do
    # Get current config snapshot
    config = case GenServer.call(__MODULE__, :get_config) do
      {:ok, conf} -> conf
      conf when is_map(conf) -> conf
    end

    # Add info logging
    require Logger
    registry_entries = Registry.lookup(Arca.Config.CallbackRegistry, :config_change)
    Logger.info("config change: notifying #{length(registry_entries)} callbacks")

    # Notify all registered callbacks with current config
    Registry.dispatch(Arca.Config.CallbackRegistry, :config_change, fn entries ->
      for {_process_pid, {id, callback_fn}} <- entries do
        # Logger.info("Calling callback #{inspect(id)} for process #{inspect(process_pid)}")
        # Execute callback in the process that requested it
        try do
          callback_fn.(config)
        rescue
          e ->
            Logger.error("Config change callback error: #{inspect(id)}: #{inspect(e)}")
        end
      end
    end)

    {:ok, :notified}
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Delay cache population to avoid ETS access rights issues
    Process.send_after(self(), :initialize_config, 0)
    {:ok, %{config: %{}, config_file: LegacyCfg.config_file()}}
  end

  @impl true
  def handle_info(:initialize_config, state) do
    # Load initial configuration
    new_state = case LegacyCfg.load() do
      {:ok, config} ->
        # Initialize cache with loaded config
        build_cache(config)
        %{state | config: config}

      {:error, reason} ->
        # Initialize with empty config if there's an error
        Map.put(state, :load_error, reason)
    end

    {:noreply, new_state}
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
    # Update in-memory config
    new_config = put_in_nested(state.config, key_path, value)

    # Write to file (always returns :ok due to async implementation)
    write_config(new_config, state.config_file)

    # Update cache
    Cache.put(key_path, value)

    # Get all paths that need notification (self and ancestors)
    paths_to_notify = get_notification_paths(key_path, new_config)

    # Send process message to handle notifications asynchronously
    Process.send(self(), {:notify_paths, paths_to_notify}, [:noconnect])

    # Return success
    {:reply, {:ok, value}, %{state | config: new_config}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    case LegacyCfg.load() do
      {:ok, config} ->
        # Clear and rebuild cache
        Cache.clear()
        build_cache(config)

        # Return success
        {:reply, {:ok, config}, %{state | config: config}}

      {:error, reason} = error ->
        {:reply, error, %{state | load_error: reason}}
    end
  end

  # Private functions

  defp normalize_key_path(key) when is_list(key), do: key

  defp normalize_key_path(key) do
    key
    |> to_string()
    |> String.split(".")
  end

  defp get_in_nested(config, key_path) do
    result = Enum.reduce_while(key_path, config, fn
      k, acc when is_map(acc) ->
        case Map.get(acc, k) do
          nil -> {:halt, nil}
          value -> {:cont, value}
        end

      _k, _acc -> {:halt, nil}
    end)

    case result do
      nil -> {:error, "Key not found"}
      value -> {:ok, value}
    end
  end

  defp put_in_nested(config, [last_key], value) do
    Map.put(config, last_key, value)
  end

  defp put_in_nested(config, [head | tail], value) do
    Map.put(
      config,
      head,
      put_in_nested(Map.get(config, head, %{}), tail, value)
    )
  end

  defp write_config(config, config_file) do
    # Generate a unique token for this write operation
    token = System.monotonic_time()

    # Register the write with the FileWatcher to avoid self-notifications
    Arca.Config.FileWatcher.register_write(token)

    # Launch an async task to write the file
    Task.start(fn ->
      result = config_file
      |> Path.expand()
      |> File.write(Jason.encode!(config, pretty: true))

      case result do
        :ok -> :ok
        {:error, reason} ->
          require Logger
          Logger.error("Failed to write config file: #{inspect(reason)}")
      end
    end)

    # Return immediately without waiting for the write to complete
    :ok
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

  defp get_notification_paths(key_path, config, paths \\ []) do
    # First add the current path with its value
    result = get_in_nested(config, key_path)

    updated_paths = case result do
      {:ok, value} -> [{key_path, value} | paths]
      _ -> paths
    end

    # Add parent paths if needed
    if length(key_path) > 1 do
      parent_path = Enum.slice(key_path, 0, length(key_path) - 1)
      parent_result = get_in_nested(config, parent_path)

      case parent_result do
        {:ok, parent_value} ->
          # Recursively get parent paths
          get_notification_paths(parent_path, config, [{parent_path, parent_value} | updated_paths])

        _ ->
          updated_paths
      end
    else
      updated_paths
    end
  end
end
