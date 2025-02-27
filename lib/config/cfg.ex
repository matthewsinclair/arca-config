defmodule Arca.Config.Cfg do
  @moduledoc """
  Provides a simple programmatic API to a set of configuration properties held in a JSON config file.

  This module automatically derives configuration paths and filenames from the parent application
  if not explicitly configured. For example, if your application is named `:my_app`, the default
  configuration path will be `~/.my_app/` and will look for environment variables like
  `MY_APP_CONFIG_PATH` unless explicitly overridden.
  """

  @doc false
  def parent_app do
    Application.get_application(Arca.Config.Cfg) || :arca_config
  end

  @doc false
  def env_var_prefix do
    parent_app() |> to_string() |> String.upcase()
  end

  @config_path_env_var "ARCA_CONFIG_PATH"
  @config_file_env_var "ARCA_CONFIG_FILE"

  @doc """
  Loads configuration from the specified file, or auto-detects from home and local paths.

  When no file is explicitly provided, it first checks for a configuration file in the 
  user's home directory (~/.app_name/config.json). If that doesn't exist, it falls back 
  to looking in the local directory (./.app_name/config.json).

  ## Parameters
    - `config_file`: The path to the configuration file (optional).

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"id": "TEST_CONFIG"}))
      iex> {:ok, cfg} = Arca.Config.Cfg.load()
      iex> cfg["id"]
      "TEST_CONFIG"
      iex> File.rm(Path.join(test_path, test_file))
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
      iex> System.put_env("ARCA_CONFIG_PATH", Path.join(System.tmp_dir!(), "test_config"))
      iex> System.put_env("ARCA_CONFIG_FILE", "test.json")
      iex> String.ends_with?(Arca.Config.Cfg.config_file(), "test.json")
      true
      iex> System.delete_env("ARCA_CONFIG_PATH")
      iex> System.delete_env("ARCA_CONFIG_FILE")
  """
  @spec config_file() :: String.t()
  def config_file do
    home_path = config_pathname()
    local_path = local_config_pathname()
    filename = config_filename()

    # Guard against nil values
    if home_path && filename do
      home_config = Path.join(home_path, filename)

      if local_path && filename do
        local_config = Path.join(local_path, filename)

        cond do
          File.exists?(Path.expand(home_config)) -> home_config
          true -> local_config
        end
      else
        home_config
      end
    else
      # Fallback to default location
      Path.join(System.tmp_dir!(), "config.json")
    end
  end

  @doc """
  Get path for the global configuration file (in user's home directory).

  Looks for configuration in the following order:
  1. Environment variable named `ARCA_CONFIG_PATH`
  2. Environment variable derived from parent app name (e.g., `MY_APP_CONFIG_PATH`)
  3. Application config under `:arca_config, :config_path`
  4. Default path based on parent application name

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", "/test/path")
      iex> Arca.Config.Cfg.config_pathname()
      "/test/path"
      iex> System.delete_env("ARCA_CONFIG_PATH")
  """
  @spec config_pathname() :: String.t()
  def config_pathname do
    app_specific_env_var = "#{env_var_prefix()}_CONFIG_PATH"

    System.get_env(@config_path_env_var) ||
      System.get_env(app_specific_env_var) ||
      Application.get_env(:arca_config, :config_path) ||
      default_config_path()
  end

  @doc """
  Get path for the local configuration file (in current working directory).

  Looks for configuration in the following order:
  1. Environment variable named `ARCA_LOCAL_CONFIG_PATH`
  2. Environment variable derived from parent app name (e.g., `MY_APP_LOCAL_CONFIG_PATH`)
  3. Application config under `:arca_config, :local_config_path`
  4. Default local path based on parent application name

  ## Examples 
      iex> System.put_env("ARCA_LOCAL_CONFIG_PATH", "/test/local/path")
      iex> Arca.Config.Cfg.local_config_pathname()
      "/test/local/path"
      iex> System.delete_env("ARCA_LOCAL_CONFIG_PATH")
  """
  @spec local_config_pathname() :: String.t()
  def local_config_pathname do
    app_specific_env_var = "#{env_var_prefix()}_LOCAL_CONFIG_PATH"

    System.get_env("ARCA_LOCAL_CONFIG_PATH") ||
      System.get_env(app_specific_env_var) ||
      Application.get_env(:arca_config, :local_config_path) ||
      local_config_path()
  end

  @doc """
  Get path for data files related to the configuration.

  ## Examples
      iex> System.put_env("ARCA_CONFIG_PATH", "/test/path")
      iex> Arca.Config.Cfg.config_data_pathname()
      "/test/path/data/links"
      iex> System.delete_env("ARCA_CONFIG_PATH")
  """
  @spec config_data_pathname() :: String.t()
  def config_data_pathname do
    Path.join([config_pathname(), "data", "links"])
  end

  @doc """
  Get name of the configuration file.

  Looks for configuration in the following order:
  1. Environment variable named `ARCA_CONFIG_FILE`
  2. Environment variable derived from parent app name (e.g., `MY_APP_CONFIG_FILE`)
  3. Application config under `:arca_config, :config_file`
  4. Default filename ("config.json")

  ## Examples
      iex> System.put_env("ARCA_CONFIG_FILE", "test.json")
      iex> Arca.Config.Cfg.config_filename()
      "test.json"
      iex> System.delete_env("ARCA_CONFIG_FILE")
  """
  @spec config_filename() :: String.t()
  def config_filename do
    app_specific_env_var = "#{env_var_prefix()}_CONFIG_FILE"

    System.get_env(@config_file_env_var) ||
      System.get_env(app_specific_env_var) ||
      Application.get_env(:arca_config, :config_file) ||
      default_config_file()
  end

  @doc """
  Inspects a configuration property by its name. Note: this will _not_ traverse the property hierarchy for nested properties.

  ## Parameters
    - `name`: The name of the property to inspect.

  ## Examples
      iex> test_path = System.tmp_dir!()
      iex> test_file = "config_test.json"
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"id": "TEST_ID"}))
      iex> Arca.Config.Cfg.inspect_property("id")
      {:ok, "TEST_ID"}
      iex> File.rm(Path.join(test_path, test_file))
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
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"database": {"host": "localhost"}}))
      iex> Arca.Config.Cfg.get("database.host")
      {:ok, "localhost"}
      iex> File.rm(Path.join(test_path, test_file))
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
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), ~s({"database": {"host": "localhost"}}))
      iex> Arca.Config.Cfg.get!("database.host")
      "localhost"
      iex> File.rm(Path.join(test_path, test_file))

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
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), "{}")
      iex> Arca.Config.Cfg.put("database.host", "127.0.0.1")
      iex> {:ok, value} = Arca.Config.Cfg.get("database.host")
      iex> value
      "127.0.0.1"
      iex> File.rm(Path.join(test_path, test_file))
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
      iex> System.put_env("ARCA_CONFIG_PATH", test_path)
      iex> System.put_env("ARCA_CONFIG_FILE", test_file)
      iex> File.write!(Path.join(test_path, test_file), "{}")
      iex> result = Arca.Config.Cfg.put!("database.host", "127.0.0.1")
      iex> result
      "127.0.0.1"
      iex> File.rm(Path.join(test_path, test_file))

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
  Returns the default configuration path based on the parent application name.

  For example, if the parent app is `:my_app`, the default path will be `~/.my_app/`.
  This can be overridden with the `:default_config_path` config option.

  This path is within the user's home directory.
  """
  def default_config_path do
    app_name = parent_app() |> to_string()
    default = "~/.#{app_name}/"

    Application.get_env(:arca_config, :default_config_path, default)
  end

  @doc """
  Returns the local configuration path based on the parent application name.

  For example, if the parent app is `:my_app`, the local path will be `./.my_app/`.
  This can be overridden with the `:local_config_path` config option.

  This path is within the current working directory.
  """
  def local_config_path do
    app_name = parent_app() |> to_string()
    default = "./.#{app_name}/"

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
