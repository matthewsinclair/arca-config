defmodule Arca.Config do
  @moduledoc """
  Arca.Config provides a simple file-based configuration utility for Elixir projects.

  It allows reading from and writing to a JSON configuration file, with support for
  nested properties using dot notation.

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
  """

  use Application

  alias Arca.Config.Server
  alias Arca.Config.Supervisor, as: ConfigSupervisor

  @doc """
  Handle Application functionality to start the Arca.Config subsystem.

  Starts the supervisor tree that manages the configuration system.
  """
  @impl true
  def start(_type, _args) do
    # Start the supervisor
    result = ConfigSupervisor.start_link([])

    # Apply environment overrides after the configuration server has started
    apply_env_overrides()

    result
  end

  @doc """
  Applies environment variable overrides to the configuration file.

  Looks for environment variables with the pattern `APP_CONFIG_OVERRIDE_SECTION_KEY`
  and applies them to the configuration file. For example, if the environment variable
  `MY_APP_CONFIG_OVERRIDE_DATABASE_HOST` is set to "localhost", it will update
  the configuration value at `database.host` to "localhost".

  This function automatically converts values to appropriate types (integer, boolean, etc.).

  ## Returns
    - `:ok` if the operation was successful
    - `{:error, reason}` if there was an error

  ## Examples
      iex> System.put_env("MY_APP_CONFIG_OVERRIDE_DATABASE_HOST", "localhost")
      iex> Arca.Config.apply_env_overrides()
      :ok
  """
  @spec apply_env_overrides() :: :ok | {:error, term()}
  def apply_env_overrides do
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
