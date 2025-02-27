defmodule Arca.Config.Test.Support do
  @moduledoc """
  Support functions for testing Arca.Config
  """

  @doc """
  Write a default config file for testing
  """
  def write_default_config_file(config_file \\ nil, config_path \\ nil) do
    # Save original env vars
    original_file = System.get_env("ARCA_CONFIG_FILE")
    original_path = System.get_env("ARCA_CONFIG_PATH")

    # Set test env vars
    if config_file, do: System.put_env("ARCA_CONFIG_FILE", config_file)
    if config_path, do: System.put_env("ARCA_CONFIG_PATH", config_path)

    config_path = config_path || System.tmp_dir!()
    config_file = config_file || "config_test.json"
    full_path = Path.join(config_path, config_file)

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(Path.expand(full_path)))

    # Write test config
    File.write!(
      Path.expand(full_path),
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )

    # Register cleanup
    on_exit = Process.get(:on_exit) || fn -> :ok end
    old_on_exit = on_exit

    Process.put(:on_exit, fn ->
      # Clean up test file
      File.rm(Path.expand(full_path))
      
      # Restore original env vars or delete if they weren't set
      if original_file, do: System.put_env("ARCA_CONFIG_FILE", original_file), else: System.delete_env("ARCA_CONFIG_FILE")
      if original_path, do: System.put_env("ARCA_CONFIG_PATH", original_path), else: System.delete_env("ARCA_CONFIG_PATH")
      
      # Call original cleanup
      old_on_exit.()
    end)

    # Return path for reference
    full_path
  end

  @doc """
  Helper to clean up after tests
  """
  def on_exit(fun) do
    ExUnit.Callbacks.on_exit(fun)
  end
end