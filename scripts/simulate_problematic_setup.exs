#!/usr/bin/env elixir

# simulate_problematic_setup.exs
#
# This script simulates a more complex setup that might trigger the path handling bug,
# particularly focusing on scenarios that would have triggered the bug previously

# Ensure the app is compiled and available
Mix.install([
  {:jason, "~> 1.2"}
])

# Clean up any existing test directories to start fresh
File.rm_rf!("./.multiplyer")

# Load the Arca.Config module
Code.require_file("lib/arca_config.ex")
Code.require_file("lib/config/cfg.ex")  
Code.require_file("lib/config/server.ex")
Code.require_file("lib/config/cache.ex")
Code.require_file("lib/config/supervisor.ex")
Code.require_file("lib/config/file_watcher.ex")
Code.require_file("lib/config/init_helper.ex")
Code.require_file("lib/config/map.ex")

defmodule ComplexSetup do
  def start do
    IO.puts("\n=== Testing Problematic Setup ===")
    
    # 1. First set config domain but not path - this should create a relative path
    Application.put_env(:arca_config, :config_domain, :multiplyer)
    IO.puts("Set config_domain to :multiplyer but no config path")
    
    # Start without paths set
    {:ok, _pid} = Arca.Config.Supervisor.start_link([])
    IO.puts("Started Arca.Config supervisor without paths set")
    
    # Show where config would be written now
    print_paths("Initial setup")
    
    # 2. Now mid-operation, change the path to an absolute path
    # This is a key scenario that would have triggered the bug before
    System.put_env("MULTIPLYER_CONFIG_PATH", "/Users/matts/.multiplyer")
    IO.puts("\nChanged environment to use absolute path DURING operation")
    
    # 3. Write a config value which should use the new path
    IO.puts("\n=== Writing config after path change ===")
    Arca.Config.put("test_key", "test_value")
    
    # Check paths again
    print_paths("After writing config")
    
    # 4. Check for recursive directory creation
    IO.puts("\n=== Checking for recursive directory creation ===")
    recursive_path = "./.multiplyer/Users/matts/.multiplyer"
    if File.exists?(recursive_path) do
      IO.puts("Recursive path exists: YES (BUG!)")
      IO.puts("Contains: #{inspect(File.ls!(recursive_path))}")
    else
      IO.puts("Recursive path exists: NO (Good)")
    end
    
    # 5. Check both locations where the file might have been written
    IO.puts("\n=== Final verification ===")
    local_config = Path.join("./.multiplyer", "config.json")
    absolute_config = Path.join("/Users/matts/.multiplyer", "config.json")
    
    IO.puts("Checking local config file (#{local_config}): #{File.exists?(local_config)}")
    IO.puts("Checking absolute config file (#{absolute_config}): #{File.exists?(absolute_config)}")
    
    if File.exists?(absolute_config) do
      IO.puts("\nContents of absolute config file:")
      {:ok, content} = File.read(absolute_config)
      IO.puts(content)
    end
    
    if File.exists?(local_config) do
      IO.puts("\nContents of local config file (should not exist or should not have latest change):")
      {:ok, content} = File.read(local_config)
      IO.puts(content)
    end
  end
  
  def print_paths(label) do
    config_file = Arca.Config.Cfg.config_file()
    expanded_path = Path.expand(config_file)
    
    IO.puts("\n=== Path Information: #{label} ===")
    IO.puts("Current directory: #{File.cwd!()}")
    IO.puts("Config file path from Cfg.config_file(): #{config_file}")
    IO.puts("Expanded config path: #{expanded_path}")
    IO.puts("Is absolute path? #{String.starts_with?(config_file, "/")}")
    IO.puts("Is expanded path absolute? #{String.starts_with?(expanded_path, "/")}")
    
    # Check both possible locations where files might be created
    check_path(expanded_path)
    if expanded_path != config_file do
      check_path(config_file)
    end
  end
  
  defp check_path(path) do
    parent_dir = Path.dirname(path)
    IO.puts("\nChecking parent dir: #{parent_dir}")
    
    if File.exists?(parent_dir) do
      IO.puts("Directory exists: YES")
      case File.ls(parent_dir) do
        {:ok, files} -> IO.puts("Contents: #{inspect(files)}")
        _ -> IO.puts("Unable to list directory contents")
      end
    else
      IO.puts("Directory exists: NO")
    end
  end
end

# Run the complex setup test
ComplexSetup.start()