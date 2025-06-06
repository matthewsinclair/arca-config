defmodule Arca.Config.Cfg do
  @moduledoc """
  Provides a simple programmatic API to a set of configuration properties held in a JSON config file.

  This module automatically derives configuration paths and filenames from the config domain
  if not explicitly configured. The config domain is determined in the following order:

  1. **Explicit configuration**: `Application.put_env(:arca_config, :config_domain, :my_app)`
  2. **Auto-detection**: Based on the parent application context
  3. **Default**: `:arca_config`

  For example, if your application is named `:my_app` and you set the config domain explicitly,
  the default configuration path will be `~/.my_app/` and will look for environment variables
  like `MY_APP_CONFIG_PATH`.

  ## Important Notes

  - Parent applications MUST set the config domain in their `Application.start/2` callback
    before calling `Arca.Config.load_config_phase/0` during the start phase
  - The config domain is checked on every access to ensure consistency
  """

  @doc false
  def config_domain do
    # Always check explicit configuration first (highest priority)
    # This ensures parent applications can override the domain at any time
    explicit_domain = Application.get_env(:arca_config, :config_domain)

    if explicit_domain do
      explicit_domain
    else
      # Auto-detect domain without caching
      try_detect_parent_app()
    end
  end

  defp try_detect_parent_app do
    # Get the OTP application for the calling module
    caller_app =
      case Process.get(:"$callers") do
        # If we have caller information
        [caller | _] when is_pid(caller) ->
          # Get the application for the calling process
          case Process.info(caller, :dictionary) do
            {:dictionary, dict} ->
              # Look up the caller's application
              case Keyword.get(dict, :"$initial_call") do
                {mod, _, _} -> Application.get_application(mod)
                _ -> nil
              end

            _ ->
              nil
          end

        _ ->
          nil
      end

    # If we found a caller app and it's not arca_config itself, use it
    if caller_app && caller_app != :arca_config do
      caller_app
    else
      # Try to find the parent application by examining the application tree
      # Get all running applications
      running_apps = Application.started_applications() |> Enum.map(fn {app, _, _} -> app end)

      # If arca_config is the only running app, use it
      if running_apps == [:arca_config] || !Enum.member?(running_apps, :arca_config) do
        :arca_config
      else
        # Try to find a non-system app that isn't arca_config
        system_apps = [
          :kernel,
          :stdlib,
          :elixir,
          :logger,
          :arca_config,
          :compiler,
          :crypto,
          :jason,
          :iex
        ]

        non_system_apps = running_apps -- system_apps

        case non_system_apps do
          # Fallback if only system apps are running
          [] -> :arca_config
          # Use the first non-system app
          [app | _] -> app
        end
      end
    end
  end

  @doc false
  def env_var_prefix do
    config_domain() |> to_string() |> String.upcase()
  end

  @doc """
  Loads configuration from the specified file, or auto-detects from configured paths.

  When no file is explicitly provided, it first checks for a configuration file in the
  configured path (.app_name/config.json).

  ## Parameters
    - `config_file`: The path to the configuration file (optional).

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"id": "TEST_CONFIG"}))
      iex> {:ok, cfg} = Arca.Config.Cfg.load()
      iex> cfg["id"]
      "TEST_CONFIG"
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec load(String.t() | nil) :: {:ok, map()} | {:error, String.t()}
  def load(config_file \\ nil) do
    file_path =
      if config_file do
        config_file
      else
        config_file()
      end

    file_path
    |> Path.expand()
    |> File.read()
    |> handle_file_read_result()
  end

  defp handle_file_read_result({:ok, content}) do
    content
    |> normalize_content()
    |> Jason.decode()
    |> handle_decode_result()
  end

  defp handle_file_read_result({:error, :enoent}) do
    # Return an empty config if the file doesn't exist
    {:ok, %{}}
  end

  defp handle_file_read_result({:error, reason}),
    do: {:error, "Failed to load config file: #{reason}"}

  defp normalize_content(""), do: "{}"
  defp normalize_content(content), do: content

  defp handle_decode_result({:ok, result}), do: {:ok, result}

  defp handle_decode_result({:error, %{position: position, token: token}}) do
    {:error, "Error parsing config at position: #{position}, token: '#{token}'"}
  end

  @doc """
  Get fully-qualified path name of the configuration file.

  Looks first in the home directory, then falls back to the local directory
  if no configuration is found in the home path.

  ## Examples
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, Path.join(System.tmp_dir!(), "test_config"))
      iex> System.put_env(app_specific_file_var, "test.json")
      iex> String.ends_with?(Arca.Config.Cfg.config_file(), "test.json")
      true
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec config_file() :: String.t()
  def config_file do
    home_path = config_pathname()
    local_path = local_config_pathname()
    filename = config_filename()

    # Guard against nil values
    if home_path && filename do
      # IMPORTANT: Always use Path.expand on path components before joining
      # This prevents creating recursive paths like .multiplyer/Users/matts/.multiplyer/
      expanded_home_path = Path.expand(home_path)
      home_config = Path.join(expanded_home_path, filename)

      # Fully expand the final path to ensure there are no relative components
      expanded_home_config = Path.expand(home_config)

      if local_path && filename do
        expanded_local_path = Path.expand(local_path)
        local_config = Path.join(expanded_local_path, filename)

        # Fully expand the local config path as well
        expanded_local_config = Path.expand(local_config)

        cond do
          File.exists?(expanded_home_config) -> expanded_home_config
          true -> expanded_local_config
        end
      else
        expanded_home_config
      end
    else
      # Fallback to default location - fully expanded
      Path.expand(Path.join(System.tmp_dir!(), "config.json"))
    end
  end

  @doc """
  Get path for the configuration file.

  Looks for configuration in the following order:
  1. Environment variable derived from parent app name (e.g., `MY_APP_CONFIG_PATH`)
  2. Environment variable named `ARCA_CONFIG_PATH`
  3. Application config under `:arca_config, :config_path`
  4. Default path based on parent application name

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/path")
      iex> Arca.Config.Cfg.config_pathname()
      "/test/path"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_pathname() :: String.t()
  def config_pathname do
    app_specific_env_var = "#{env_var_prefix()}_CONFIG_PATH"
    default_arca_env_var = "ARCA_CONFIG_PATH"

    path =
      System.get_env(app_specific_env_var) ||
        System.get_env(default_arca_env_var) ||
        Application.get_env(:arca_config, :config_path) ||
        default_config_path()

    # Return path exactly as found in environment variable to ensure tests pass
    # that expect exact string matching with trailing slashes preserved
    if System.get_env(app_specific_env_var) || System.get_env(default_arca_env_var) do
      path
    else
      # Only expand path when not from environment variable
      Path.expand(path)
    end
  end

  @doc """
  Get path for the local configuration file (in current working directory).

  Looks for configuration in the following order:
  1. Environment variable derived from parent app name (e.g., `MY_APP_LOCAL_CONFIG_PATH`)
  2. Environment variable named `ARCA_LOCAL_CONFIG_PATH`
  3. Application config under `:arca_config, :local_config_path`
  4. Default local path based on parent application name

  ## Examples 
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_LOCAL_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/local/path")
      iex> Arca.Config.Cfg.local_config_pathname()
      "/test/local/path"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec local_config_pathname() :: String.t()
  def local_config_pathname do
    app_specific_env_var = "#{env_var_prefix()}_LOCAL_CONFIG_PATH"
    default_arca_env_var = "ARCA_LOCAL_CONFIG_PATH"

    path =
      System.get_env(app_specific_env_var) ||
        System.get_env(default_arca_env_var) ||
        Application.get_env(:arca_config, :local_config_path) ||
        local_config_path()

    # Return expanded path to avoid path joining issues
    Path.expand(path)
  end

  @doc """
  Get path for data files related to the configuration.

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> System.put_env(app_specific_env_var, "/test/path")
      iex> Arca.Config.Cfg.config_data_pathname()
      "/test/path/data/links"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_data_pathname() :: String.t()
  def config_data_pathname do
    Path.join([config_pathname(), "data", "links"])
  end

  @doc """
  Get name of the configuration file.

  Looks for configuration in the following order:
  1. Environment variable derived from parent app name (e.g., `MY_APP_CONFIG_FILE`)
  2. Environment variable named `ARCA_CONFIG_FILE`
  3. Application config under `:arca_config, :config_file`
  4. Default filename ("config.json")

  ## Examples
      iex> app_specific_env_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_env_var, "test.json")
      iex> Arca.Config.Cfg.config_filename()
      "test.json"
      iex> System.delete_env(app_specific_env_var)
  """
  @spec config_filename() :: String.t()
  def config_filename do
    app_specific_env_var = "#{env_var_prefix()}_CONFIG_FILE"
    default_arca_env_var = "ARCA_CONFIG_FILE"

    filename =
      System.get_env(app_specific_env_var) ||
        System.get_env(default_arca_env_var) ||
        Application.get_env(:arca_config, :config_file) ||
        default_config_file()

    # If filename contains a path, extract just the filename part
    # This prevents issues like joining .multiplyer/ with /Users/matts/.multiplyer/config.json
    if String.contains?(filename, "/") do
      Path.basename(filename)
    else
      filename
    end
  end

  @doc """
  Inspects a configuration property by its name. Note: this will _not_ traverse the property hierarchy for nested properties.

  ## Parameters
    - `name`: The name of the property to inspect.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"id": "TEST_ID"}))
      iex> Arca.Config.Cfg.inspect_property("id")
      {:ok, "TEST_ID"}
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec inspect_property(String.t() | atom()) :: {:ok, any()} | {:error, String.t()}
  def inspect_property(name) do
    with {:ok, config} <- load(),
         value when not is_nil(value) <- Map.get(config, name) do
      {:ok, value}
    else
      nil -> {:error, "No such property: #{inspect(name)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Provides a map-style accessor to the configuration properties.

  ## Parameters
    - `key`: The key to retrieve from the configuration.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"database": {"host": "localhost"}}))
      iex> Arca.Config.Cfg.get("database.host")
      {:ok, "localhost"}
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec get(String.t() | atom()) :: {:ok, any()} | {:error, String.t()}
  def get(key) do
    with {:ok, config} <- load() do
      key
      |> to_string()
      |> String.split(".")
      |> Enum.reduce_while(config, fn
        k, acc when is_map(acc) -> {:cont, Map.get(acc, k)}
        _, _ -> {:halt, nil}
      end)
      |> case do
        nil -> {:error, "'#{key}' not found"}
        value -> {:ok, value}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the configuration property and raises an error if not found.

  ## Parameters
    - `key`: The key to retrieve from the configuration.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"database": {"host": "localhost"}}))
      iex> Arca.Config.Cfg.get!("database.host")
      "localhost"
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)

  ## Raises
    - `RuntimeError`: If the key is not found in the configuration.
  """
  @spec get!(String.t() | atom()) :: any() | no_return()
  def get!(key) do
    case get(key) do
      {:ok, value} -> value
      {:error, reason} -> raise RuntimeError, message: reason
    end
  end

  @doc """
  Updates a value in the configuration and returns `{:ok, value}` or `{:error, reason}`.

  ## Parameters
    - `key`: The key to update in the configuration.
    - `value`: The new value to set for the key.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), "{}")
      iex> Arca.Config.Cfg.put("database.host", "127.0.0.1")
      iex> {:ok, value} = Arca.Config.Cfg.get("database.host")
      iex> value
      "127.0.0.1"
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)
  """
  @spec put(String.t() | atom(), any()) :: {:ok, any()} | {:error, String.t()}
  def put(key, value) do
    with {:ok, config} <- load() do
      keys = String.split(to_string(key), ".")
      updated_config = update_nested_config(config, keys, value)

      case write_config(updated_config) do
        :ok -> {:ok, value}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a value in the configuration and raises an error if the operation fails.

  ## Parameters
    - `key`: The key to update in the configuration.
    - `value`: The new value to set for the key.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> app_specific_path_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_PATH"
      iex> app_specific_file_var = Arca.Config.Cfg.env_var_prefix() <> "_CONFIG_FILE"
      iex> System.put_env(app_specific_path_var, test_path)
      iex> System.put_env(app_specific_file_var, test_file)
      iex> File.write!(Path.join(test_path, test_file), "{}")
      iex> result = Arca.Config.Cfg.put!("database.host", "127.0.0.1")
      iex> result
      "127.0.0.1"
      iex> File.rm(Path.join(test_path, test_file))
      iex> System.delete_env(app_specific_path_var)
      iex> System.delete_env(app_specific_file_var)

  ## Raises
    - `RuntimeError`: If the update operation fails.
  """
  @spec put!(String.t() | atom(), any()) :: any() | no_return()
  def put!(key, value) do
    case put(key, value) do
      {:ok, value} -> value
      {:error, reason} -> raise RuntimeError, message: reason
    end
  end

  defp update_nested_config(config, [last_key], value) do
    Map.put(config, last_key, value)
  end

  defp update_nested_config(config, [head | tail], value) do
    updated_subconfig = update_nested_config(Map.get(config, head, %{}), tail, value)
    Map.put(config, head, updated_subconfig)
  end

  defp write_config(config, config_file \\ config_file()) do
    config_file
    |> Path.expand()
    |> File.write(Jason.encode!(config, pretty: true))
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the default configuration path based on the config domain name.

  For example, if the config domain is `:my_app`, the default path will be `.my_app/`.
  This can be overridden with the `:default_config_path` config option.

  This path is within the current working directory.
  """
  def default_config_path do
    app_name = config_domain() |> to_string()
    default = ".#{app_name}/"

    Application.get_env(:arca_config, :default_config_path, default)
  end

  @doc """
  Returns the local configuration path based on the config domain name.

  For example, if the config domain is `:my_app`, the local path will be `.my_app/`.
  This can be overridden with the `:local_config_path` config option.

  This path is within the current working directory.
  """
  def local_config_path do
    app_name = config_domain() |> to_string()
    default = ".#{app_name}/"

    Application.get_env(:arca_config, :local_config_path, default)
  end

  @doc """
  Returns the default configuration filename.

  The default is "config.json" but this can be overridden with the 
  `:default_config_file` config option.
  """
  def default_config_file do
    Application.get_env(:arca_config, :default_config_file, "config.json")
  end
end
