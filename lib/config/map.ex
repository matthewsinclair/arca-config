defmodule Arca.Config.Map do
  @moduledoc """
  Provides a Map-like interface to access configuration values.
  
  This module implements the Access behavior, allowing for a syntax like:
  
      config = Arca.Config.Map.new()
      config[:database][:host]
  
  It also provides function-based access similar to Map:
  
      Arca.Config.Map.get(config, :database)
      Arca.Config.Map.get_in(config, [:database, :host])
  """
  
  alias Arca.Config.Server
  
  defstruct []
  
  @type t :: %__MODULE__{}
  
  # Explicitly declare that we're implementing the Access behaviour
  @behaviour Access
  
  @doc """
  Creates a new configuration map wrapper.
  
  ## Returns
    - A new configuration map struct
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}
  
  @doc """
  Gets a value from the configuration.
  
  ## Parameters
    - `config`: The configuration map
    - `key`: The key to get
    - `default`: A default value to return if the key is not found
  
  ## Returns
    - The value if found, or the default value
  """
  @spec get(t(), any(), any()) :: any()
  def get(%__MODULE__{}, key, default \\ nil) do
    case Server.get(key) do
      {:ok, value} -> value
      {:error, _} -> default
    end
  end
  
  @doc """
  Gets a value from a nested path in the configuration.
  
  ## Parameters
    - `config`: The configuration map
    - `keys`: A list of keys to traverse
    - `default`: A default value to return if the path is not found
  
  ## Returns
    - The value if found, or the default value
  """
  @spec get_in(t(), [any()], any()) :: any()
  def get_in(%__MODULE__{}, keys, default \\ nil) do
    case Server.get(keys) do
      {:ok, value} -> value
      {:error, _} -> default
    end
  end
  
  @doc """
  Puts a value in the configuration.
  
  ## Parameters
    - `config`: The configuration map
    - `key`: The key to set
    - `value`: The value to set
  
  ## Returns
    - A new configuration map with the updated value
  """
  @spec put(t(), any(), any()) :: t()
  def put(%__MODULE__{} = config, key, value) do
    case Server.put(key, value) do
      {:ok, _} -> config
      {:error, reason} -> raise RuntimeError, message: "Failed to put config: #{reason}"
    end
  end
  
  @doc """
  Puts a value at a nested path in the configuration.
  
  ## Parameters
    - `config`: The configuration map
    - `keys`: A list of keys to traverse
    - `value`: The value to set
  
  ## Returns
    - A new configuration map with the updated value
  """
  @spec put_in(t(), [any()], any()) :: t()
  def put_in(%__MODULE__{} = config, keys, value) do
    case Server.put(keys, value) do
      {:ok, _} -> config
      {:error, reason} -> raise RuntimeError, message: "Failed to put config: #{reason}"
    end
  end
  
  @doc """
  Checks if a key exists in the configuration.
  
  ## Parameters
    - `config`: The configuration map
    - `key`: The key to check
  
  ## Returns
    - `true` if the key exists, `false` otherwise
  """
  @spec has_key?(t(), any()) :: boolean()
  def has_key?(%__MODULE__{}, key) do
    case Server.get(key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
  
  # Implement Access behavior for bracket access syntax
  
  @impl Access
  def fetch(%__MODULE__{}, key) do
    case Server.get(key) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> :error
    end
  end
  
  @impl Access
  def get_and_update(%__MODULE__{} = config, key, fun) do
    current_value = get(config, key)
    
    case fun.(current_value) do
      {get_value, update_value} ->
        {get_value, put(config, key, update_value)}
      
      :pop ->
        # Since we can't really delete keys, we'll return nil
        {current_value, config}
    end
  end
  
  @impl Access
  def pop(%__MODULE__{} = config, key) do
    current_value = get(config, key)
    {current_value, config}
  end
end