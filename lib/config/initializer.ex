defmodule Arca.Config.Initializer do
  @moduledoc """
  GenServer that handles delayed initialization of the Arca.Config system.

  This module helps prevent circular dependencies during application startup by:
  1. Delaying configuration loading until after application startup
  2. Using process identity checks to prevent circular calls
  3. Adding safeguards against recursive configuration access
  4. Using a registry pattern for callbacks instead of direct function calls
  """

  use GenServer
  require Logger

  alias Arca.Config.Cache
  alias Arca.Config.Cfg, as: LegacyCfg

  # Delay in milliseconds before initialization
  @initialization_delay 500

  # Client API

  @doc """
  Starts the configuration initializer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Registers a callback to be run after initialization is complete.
  This prevents circular dependencies during application startup.

  ## Parameters
    - `callback_id`: A unique identifier for the callback
    - `callback_fn`: A function that takes no arguments to be called after initialization
  """
  @spec register_after_init(term(), (-> any())) :: {:ok, :registered}
  def register_after_init(callback_id, callback_fn) when is_function(callback_fn, 0) do
    GenServer.call(__MODULE__, {:register_after_init, callback_id, callback_fn})
  end

  @doc """
  Checks if the initializer has completed its initialization.

  ## Returns
    - `true` if initialization is complete
    - `false` if initialization is still in progress
  """
  @spec initialized?() :: boolean()
  def initialized? do
    GenServer.call(__MODULE__, :initialized?)
  end

  @doc """
  Gets the process identity of the caller, used to prevent circular dependencies.

  ## Returns
    - PID of the calling process
  """
  @spec get_process_identity() :: pid()
  def get_process_identity do
    self()
  end

  @doc """
  Triggers initialization manually (for testing).

  This function is primarily useful in test environments where
  you need to ensure initialization is complete before testing.
  """
  @spec force_initialize() :: :ok
  def force_initialize do
    GenServer.cast(__MODULE__, :initialize_now)
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Schedule delayed initialization
    Process.send_after(self(), :initialize_config, @initialization_delay)

    # Start with conservative defaults
    {:ok,
     %{
       initialized: false,
       initializing: false,
       initialization_process: nil,
       after_init_callbacks: %{}
     }}
  end

  @impl true
  def handle_info(:initialize_config, state) do
    if state.initializing do
      Logger.warning("Initialization already in progress, ignoring duplicate request")
      {:noreply, state}
    else
      # # Mark that we're starting initialization
      # Logger.info("Starting delayed configuration initialization")

      # Track the process doing the initialization to prevent circular dependencies
      new_state = %{state | initializing: true, initialization_process: self()}

      # Perform initialization
      new_state = do_initialize(new_state)

      # Run after-init callbacks
      run_after_init_callbacks(new_state.after_init_callbacks)

      # Update state to reflect completed initialization
      {:noreply, %{new_state | initialized: true, initializing: false}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_call({:register_after_init, callback_id, callback_fn}, _from, state) do
    # If already initialized, run the callback immediately
    # Check state directly instead of calling initialized? to avoid circular calls
    if state.initialized do
      safely_run_callback(callback_id, callback_fn)
      {:reply, {:ok, :registered}, state}
    else
      # Store the callback for later execution
      updated_callbacks = Map.put(state.after_init_callbacks, callback_id, callback_fn)
      {:reply, {:ok, :registered}, %{state | after_init_callbacks: updated_callbacks}}
    end
  end

  @impl true
  def handle_cast(:initialize_now, state) do
    if state.initialized do
      {:noreply, state}
    else
      send(self(), :initialize_config)
      {:noreply, state}
    end
  end

  # Private functions

  defp do_initialize(state) do
    # Load initial configuration
    case LegacyCfg.load() do
      {:ok, config} ->
        # Initialize cache with loaded config
        Cache.clear()
        build_cache(config)

        # Apply environment overrides after loading config
        Arca.Config.apply_env_overrides()

        # # For debugging
        # Logger.debug("Initialized with config: #{inspect(config)}")

        %{state | initialized: true, initializing: false, initialization_process: nil}

      {:error, reason} ->
        # Log error but continue with empty config
        Logger.error("Failed to load initial configuration: #{reason}")
        Cache.clear()
        build_cache(%{})

        # Apply environment overrides even with an empty config
        Arca.Config.apply_env_overrides()

        %{state | initialized: true, initializing: false, initialization_process: nil}
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

  defp run_after_init_callbacks(callbacks) do
    # count = map_size(callbacks)
    # Logger.info("Running #{count} delayed initialization callbacks")

    for {id, callback_fn} <- callbacks do
      safely_run_callback(id, callback_fn)
    end
  end

  defp safely_run_callback(id, callback_fn) do
    try do
      # Execute the callback in a rescue block to prevent crashes
      callback_fn.()
    rescue
      e ->
        # Log errors but don't crash the initializer
        Logger.error("Error in initialization callback #{inspect(id)}: #{inspect(e)}")
    catch
      kind, reason ->
        # Also catch throws, exits, etc.
        Logger.error("Caught #{kind} in callback #{inspect(id)}: #{inspect(reason)}")
    end
  end
end
