defmodule Arca.Config do
  @moduledoc """
  Arca.Config provides a simple file-based configuration utility for Elixir projects.

  It allows reading from and writing to a JSON configuration file, with support for
  nested properties using dot notation.

  ## OTP Start Phase Integration

  **IMPORTANT**: Starting from this version, Arca.Config uses OTP start phases for
  deterministic configuration loading. Parent applications MUST:

  1. Set the config domain in their `Application.start/2` callback:
     ```elixir
     def start(_type, _args) do
       Application.put_env(:arca_config, :config_domain, :my_app)
       # ... start supervisor tree
     end
     ```

  2. Implement the `:load_config` start phase:
     ```elixir
     def start_phase(:load_config, _start_type, _phase_args) do
       Arca.Config.load_config_phase()
     end
     ```

  3. Define start phases in mix.exs:
     ```elixir
     def application do
       [
         extra_applications: [:logger],
         start_phases: [load_config: []]
       ]
     end
     ```

  ## Usage

  The configuration system supports both a railway-oriented programming style:

      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> {:ok, _} = Arca.Config.put("test_key", "test_value")
      iex> Arca.Config.get("test_key")
      {:ok, "test_value"}

  And a Map-like interface via Arca.Config.Map:

      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> {:ok, _} = Arca.Config.put("sample", "value")
      iex> config = Arca.Config.Map.new()
      iex> config["sample"]
      "value"

  ## Runtime Config Location Switching

  Arca.Config supports changing the configuration file location at runtime, which is
  particularly useful for testing scenarios where different tests need different configurations:

      # Switch to test configuration
      {:ok, previous_location} = Arca.Config.switch_config_location(
        path: "/tmp/test_config",
        file: "test.json"
      )

      # Your test code here...

      # Restore previous configuration
      Arca.Config.switch_config_location(previous_location)

  ### Example: Environment-based Configuration

      # Development config
      dev_config = %{
        "environment" => "development",
        "database" => %{"host" => "localhost", "port" => 5432},
        "debug" => true
      }

      # Test config
      test_config = %{
        "environment" => "test",
        "database" => %{"host" => "test-db", "port" => 5433},
        "debug" => false
      }

      # Switch between environments
      {:ok, _} = Arca.Config.switch_config_location(
        path: "config/dev",
        file: "config.json"
      )

      # In tests, switch to test config
      {:ok, original} = Arca.Config.switch_config_location(
        path: "config/test",
        file: "test.json"
      )

      # Run tests...

      # Restore original config
      Arca.Config.switch_config_location(original)

  The `switch_config_location/1` function handles:
  - Stopping the current FileWatcher
  - Clearing the configuration cache
  - Loading configuration from the new location
  - Restarting the FileWatcher on the new location
  - Notifying all registered callbacks
  """

  use Application

  alias Arca.Config.Server
  alias Arca.Config.Supervisor, as: ConfigSupervisor

  @doc """
  Handle Application functionality to start the Arca.Config subsystem.

  Starts the supervisor tree that manages the configuration system.
  Configuration loading is handled through OTP start phases.
  """
  @impl true
  def start(_type, _args) do
    # Start the supervisor - configuration will be loaded during start phase
    ConfigSupervisor.start_link([])
  end

  @doc """
  Loads configuration during the :load_config start phase.

  This function should be called by parent applications during their
  start phase implementation. It:

  1. Loads initial configuration from file
  2. Initializes the cache
  3. Starts file watching
  4. Applies environment variable overrides

  ## Returns
    - `:ok` if configuration was loaded successfully
    - `{:error, reason}` if there was an error
    
  ## Examples
      # In your application's start phase handler:
      def start_phase(:load_config, _start_type, _phase_args) do
        Arca.Config.load_config_phase()
      end
  """
  @spec load_config_phase() :: :ok | {:error, term()}
  def load_config_phase do
    # Load initial configuration
    case Server.load_config() do
      {:ok, _config} ->
        # Start file watching now that config is loaded
        Arca.Config.FileWatcher.start_watching()

        # Apply environment overrides
        apply_env_overrides()

        :ok

      {:error, reason} ->
        # Still start file watching and apply overrides even if config load failed
        Arca.Config.FileWatcher.start_watching()
        apply_env_overrides()

        {:error, reason}
    end
  end

  defp apply_env_overrides do
    # Get the prefix for environment variables
    env_prefix = Arca.Config.Cfg.env_var_prefix()
    override_prefix = "#{env_prefix}_CONFIG_OVERRIDE_"

    # Get all environment variables with the override prefix
    System.get_env()
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, override_prefix) end)
    |> Enum.each(fn {key, value} ->
      # Extract the configuration key path from the environment variable
      key_path =
        key
        |> String.replace_prefix(override_prefix, "")
        |> String.downcase()
        |> String.replace("_", ".")

      # Convert the value to the appropriate type
      converted_value = try_convert_value(value)

      # Update the configuration
      put(key_path, converted_value)
    end)

    :ok
  end

  @doc """
  Gets a configuration value.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, value}` if the key exists
    - `{:error, reason}` if the key doesn't exist or another error occurs

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> {:ok, _} = Arca.Config.put("app.name", "MyApp")
      iex> Arca.Config.get("app.name")
      {:ok, "MyApp"}
  """
  @spec get(String.t() | atom() | list()) :: {:ok, any()} | {:error, term()}
  def get(key), do: Server.get(key)

  @doc """
  Gets a configuration value or raises an error if not found.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - The configuration value if the key exists

  ## Raises
    - `RuntimeError` if the key doesn't exist or another error occurs

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> Arca.Config.put!("app.name", "MyApp")
      "MyApp"
      iex> Arca.Config.get!("app.name")
      "MyApp"
  """
  @spec get!(String.t() | atom() | list()) :: any() | no_return()
  def get!(key), do: Server.get!(key)

  @doc """
  Updates a configuration value.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys
    - `value`: The new value to set

  ## Returns
    - `{:ok, value}` if the update was successful
    - `{:error, reason}` if an error occurred

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> {:ok, value} = Arca.Config.put("database.host", "localhost")
      iex> value
      "localhost"
  """
  @spec put(String.t() | atom() | list(), any()) :: {:ok, any()} | {:error, term()}
  def put(key, value), do: Server.put(key, value)

  @doc """
  Updates a configuration value or raises an error if the operation fails.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys
    - `value`: The new value to set

  ## Returns
    - The value if the update was successful

  ## Raises
    - `RuntimeError` if an error occurred

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> Arca.Config.put!("database.host", "localhost")
      "localhost"
  """
  @spec put!(String.t() | atom() | list(), any()) :: any() | no_return()
  def put!(key, value), do: Server.put!(key, value)

  @doc """
  Subscribes to changes to a specific configuration key.

  When the value at this key changes, a message of the format
  `{:config_updated, key_path, new_value}` will be sent to the caller.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, :subscribed}` if the subscription was successful

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.Registry)
      iex> Arca.Config.subscribe("test_key")
      {:ok, :subscribed}
  """
  @spec subscribe(String.t() | atom() | list()) :: {:ok, :subscribed}
  def subscribe(key), do: Server.subscribe(key)

  @doc """
  Unsubscribes from changes to a specific configuration key.

  ## Parameters
    - `key`: A string with dot notation, atom, or list of keys

  ## Returns
    - `{:ok, :unsubscribed}` if the unsubscription was successful

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", System.tmp_dir!())
      iex> System.put_env("ARCA_CONFIG_FILE", "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), "{}")
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.Registry)
      iex> Arca.Config.unsubscribe("test_key")
      {:ok, :unsubscribed}
  """
  @spec unsubscribe(String.t() | atom() | list()) :: {:ok, :unsubscribed}
  def unsubscribe(key), do: Server.unsubscribe(key)

  @doc """
  Registers a callback function to be called when the configuration changes externally.

  This function is useful for reacting to configuration changes that happen outside
  the application, such as when the configuration file is edited directly.

  ## Parameters
    - `callback_id`: A unique identifier for the callback (used for unregistering)
    - `callback_fn`: A function that takes the entire config map as its only parameter

  ## Returns
    - `{:ok, :registered}` if the registration was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.CallbackRegistry)
      iex> callback_fn = fn config -> IO.puts("Config changed: \#{inspect(config)}") end
      iex> Arca.Config.register_change_callback(:my_callback, callback_fn)
      {:ok, :registered}
  """
  @spec register_change_callback(term(), (map() -> any())) :: {:ok, :registered}
  def register_change_callback(callback_id, callback_fn),
    do: Server.register_change_callback(callback_id, callback_fn)

  @doc """
  Unregisters a previously registered callback function.

  ## Parameters
    - `callback_id`: The identifier of the callback to unregister

  ## Returns
    - `{:ok, :unregistered}` if the unregistration was successful

  ## Examples
      iex> Registry.start_link(keys: :duplicate, name: Arca.Config.CallbackRegistry)
      iex> Arca.Config.unregister_change_callback(:my_callback)
      {:ok, :unregistered}
  """
  @spec unregister_change_callback(term()) :: {:ok, :unregistered}
  def unregister_change_callback(callback_id), do: Server.unregister_change_callback(callback_id)

  @doc """
  Adds a callback function to be called whenever the configuration changes.
  This callback does not receive any arguments, unlike `register_change_callback/2`.

  ## Parameters
    - `callback_fn`: A 0-arity function to execute when config changes

  ## Returns
    - `{:ok, reference}` if the registration was successful, where reference is used to remove the callback

  ## Examples
      iex> callback_fn = fn -> IO.puts("Config changed!") end
      iex> {:ok, _ref} = Arca.Config.add_callback(callback_fn)
  """
  @spec add_callback(function()) :: {:ok, reference()}
  def add_callback(callback_fn) when is_function(callback_fn, 0),
    do: Server.add_callback(callback_fn)

  @doc """
  Removes a previously registered callback function.

  ## Parameters
    - `callback_ref`: The reference returned by `add_callback/1`

  ## Returns
    - `{:ok, :removed}` if the callback was successfully removed
    - `{:error, :not_found}` if the callback wasn't registered

  ## Examples
      iex> callback_fn = fn -> IO.puts("Config changed!") end
      iex> {:ok, ref} = Arca.Config.add_callback(callback_fn)
      iex> Arca.Config.remove_callback(ref)
      {:ok, :removed}
  """
  @spec remove_callback(reference()) :: {:ok, :removed} | {:error, :not_found}
  def remove_callback(callback_ref), do: Server.remove_callback(callback_ref)

  @doc """
  Manually triggers notification of all registered callbacks.
  This can be useful when you want to force notification after a series of changes.

  ## Returns
    - `{:ok, :notified}` after all callbacks have been executed

  ## Examples
      iex> Arca.Config.notify_callbacks()
      {:ok, :notified}
  """
  @spec notify_callbacks() :: {:ok, :notified}
  def notify_callbacks(), do: Server.notify_callbacks()

  @doc """
  Switches the configuration file location at runtime.

  This function allows you to change where Arca.Config reads and writes
  configuration data. It performs the following operations:

  1. Stops the current FileWatcher
  2. Updates environment variables with new location
  3. Clears the configuration cache
  4. Loads configuration from the new location
  5. Restarts the FileWatcher on the new location
  6. Notifies all callbacks of the change

  ## Parameters
    - `opts`: Keyword list with optional `:path` and `:file` keys
      - `:path` - The new configuration directory path
      - `:file` - The new configuration filename

  ## Returns
    - `{:ok, previous_location}` with the previous path and file settings
    - `{:error, reason}` if an error occurred

  ## Examples
      iex> {:ok, old_location} = Arca.Config.switch_config_location(
      ...>   path: "/tmp/test_config",
      ...>   file: "test.json"
      ...> )
      iex> # Restore previous location
      iex> Arca.Config.switch_config_location(old_location)
  """
  @spec switch_config_location(keyword()) :: {:ok, keyword()} | {:error, term()}
  def switch_config_location(opts \\ []) do
    Server.switch_config_location(opts)
  end

  @doc """
  Reloads the configuration from disk.

  ## Returns
    - `{:ok, config}` with the loaded configuration if successful
    - `{:error, reason}` if an error occurred

  ## Examples
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, System.tmp_dir!())
      iex> System.put_env(app_specific_file_var, "doctest_config.json")
      iex> File.write!(Path.join(System.tmp_dir(), "doctest_config.json"), ~s({"app": {"name": "MyApp"}}))
      iex> {:ok, config} = Arca.Config.reload()
      iex> config["app"]["name"]
      "MyApp"
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec reload() :: {:ok, map()} | {:error, term()}
  def reload, do: Server.reload()

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

      ["watch", key | _] ->
        handle_watch(key)

      _ ->
        cli_spec()
        |> Optimus.parse!(argv)
        |> process_command()
    end
  end

  defp cli_spec do
    Optimus.new!(
      name: Application.get_env(:arca_config, :name, "arca_config"),
      description:
        Application.get_env(
          :arca_config,
          :description,
          "A simple file-based configurator for Elixir apps"
        ),
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
        ],
        watch: [
          name: "watch",
          about: "Watch for changes to a configuration key",
          args: [
            key: [
              value_name: "KEY",
              help: "The configuration key to watch (e.g., 'database.host')",
              required: true
            ]
          ]
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

  defp process_command({[:watch], %{args: %{key: key}}}) do
    handle_watch(key)
  end

  defp process_command(_) do
    IO.puts("Invalid command. Use --help for usage information.")
    :ok
  end

  defp handle_get(key) do
    case get(key) do
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

    case put(key, value) do
      {:ok, _} ->
        IO.puts("Successfully set '#{key}' to '#{inspect(value)}'")

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp handle_list do
    case reload() do
      {:ok, config} ->
        IO.puts(Jason.encode!(config, pretty: true))

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp handle_watch(key) do
    # Subscribe to changes for the key
    subscribe(key)

    # Print initial value
    IO.puts("Watching #{key}. Current value:")
    handle_get(key)
    IO.puts("\nWaiting for changes... (Press Ctrl+C to exit)")

    # Listen for changes
    watch_loop(key)
  end

  defp watch_loop(key) do
    receive do
      {:config_updated, key_path, value} ->
        formatted_key = Enum.join(key_path, ".")
        IO.puts("\nConfig updated: #{formatted_key}")

        if is_map(value) do
          IO.puts(Jason.encode!(value, pretty: true))
        else
          IO.puts(inspect(value))
        end

        watch_loop(key)
    end
  end

  defp try_convert_value(value) do
    cond do
      value == "true" ->
        true

      value == "false" ->
        false

      Regex.match?(~r/^-?\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^-?\d+\.\d+$/, value) ->
        String.to_float(value)

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

      true ->
        value
    end
  end
end
