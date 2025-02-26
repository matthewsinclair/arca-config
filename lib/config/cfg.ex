defmodule Arca.Config.Cfg do
  @moduledoc """
  Provides a simple programmatic API to a set of configuration properties held in a JSON config file.
  """

  @config_path_env_var "ARCA_CONFIG_PATH"
  @config_file_env_var "ARCA_CONFIG_FILE"

  @doc """
  Loads configuration from the specified file. Defaults to "config.json" if no file is provided.

  ## Parameters
    - `config_file`: The path to the configuration file (optional).

  ## Examples
      iex> Arca.Config.Test.Support.write_default_config_file(System.get_env("ARCA_CONFIG_FILE"), System.get_env("ARCA_CONFIG_PATH"))
      iex> {:ok, cfg} = Arca.Config.Cfg.load()
      ...> cfg["id"]
      "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load(config_file \\ config_file()) do
    config_file
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

  ## Examples
      iex> Arca.Config.Cfg.config_file()
      ".arca/config.json"
  """
  @spec config_file() :: String.t()
  def config_file do
    Path.join(config_pathname(), config_filename())
  end

  @doc """
  Get path for the configuration file, trying to pull from the environment variable `ARCA_CONFIG_PATH`.

  ## Examples
      iex> Arca.Config.Cfg.config_pathname()
      ".arca"
  """
  @spec config_pathname() :: String.t()
  def config_pathname do
    System.get_env(@config_path_env_var) ||
      Application.get_env(:arca_config, :config_path) ||
      default_config_path()
  end

  @doc """
  Get path for data files related to the configuration.

  ## Examples
      iex> Arca.Config.Cfg.config_data_pathname()
      ".arca/data/links"
  """
  @spec config_data_pathname() :: String.t()
  def config_data_pathname do
    Path.join([config_pathname(), "data", "links"])
  end

  @doc """
  Get name of the configuration file, trying to pull from the environment variable `ARCA_CONFIG_FILE`.

  ## Examples
      iex> Arca.Config.Cfg.config_filename()
      "config.json"
  """
  @spec config_filename() :: String.t()
  def config_filename do
    System.get_env(@config_file_env_var) ||
      Application.get_env(:arca_config, :config_file) ||
      default_config_file()
  end

  @doc """
  Inspects a configuration property by its name. Note: this will _not_ traverse the property hierarchy for nested properties.

  ## Parameters
    - `name`: The name of the property to inspect.

  ## Examples
      iex> Arca.Config.Cfg.put("id", "ID")
      iex> Arca.Config.Cfg.inspect_property("id")
      {:ok, "ID"}
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
      iex> Arca.Config.Cfg.put("database.host", "localhost")
      iex> Arca.Config.Cfg.get("database.host")
      {:ok, "localhost"}
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
      iex> Arca.Config.Cfg.put!("database.host", "localhost")
      iex> Arca.Config.Cfg.get!("database.host")
      "localhost"

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
      iex> Arca.Config.Cfg.put("database.host", "127.0.0.1")
      {:ok, "127.0.0.1"}
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
      iex> Arca.Config.Cfg.put!("database.host", "127.0.0.1")
      "127.0.0.1"

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

  defp default_config_path do
    Application.get_env(:arca_config, :default_config_path, "~/.arca/")
  end

  defp default_config_file do
    Application.get_env(:arca_config, :default_config_file, "config.json")
  end
end
