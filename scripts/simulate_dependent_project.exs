#!/usr/bin/env elixir

# simulate_dependent_project.exs
#
# This script simulates how a dependent project might interact with Arca.Config
# to help identify why our fix isn't working as expected in dependent projects

# Ensure the app is compiled and available
Mix.install([
  {:jason, "~> 1.2"}
])

# Load the Arca.Config module
Code.require_file("lib/arca_config.ex")
Code.require_file("lib/config/cfg.ex")  
Code.require_file("lib/config/server.ex")
Code.require_file("lib/config/cache.ex")
Code.require_file("lib/config/supervisor.ex")
Code.require_file("lib/config/file_watcher.ex")
Code.require_file("lib/config/init_helper.ex")
Code.require_file("lib/config/map.ex")

# Define a simple ConfigManager like what might exist in a dependent project
defmodule Multiplyer.Ta.Llm.ConfigManager do
  # Simulate a config manager that reads from Arca.Config
  def get_llm_client_type do
    case Arca.Config.get("llm_client_type") do
      {:ok, value} -> value
      _ -> "default"
    end
  end
  
  def set_llm_client_type(client_type) do
    Arca.Config.put("llm_client_type", client_type)
  end
end

# Define a simple Application module to simulate application initialization
defmodule DependentProject.Application do
  # Simulate application startup with config initialization
  def start do
    IO.puts("\n=== Initializing Dependent Project ===")
    
    # Set up config file path using both methods:
    # 1. Using Application.put_env (common in dependent projects)
    absolute_path = "/Users/matts/.multiplyer"
    IO.puts("Setting config path to: #{absolute_path}")
    
    # Method 1: Application env (often used in dependent projects)
    Application.put_env(:arca_config, :config_domain, :multiplyer)
    IO.puts("Set config_domain to :multiplyer")
    
    # Method 2: Environment variables (as recommended)
    System.put_env("MULTIPLYER_CONFIG_PATH", absolute_path)
    System.put_env("MULTIPLYER_CONFIG_FILE", "config.json")
    IO.puts("Set environment variables for config path and file")
    
    # Start Arca.Config application
    {:ok, _pid} = Arca.Config.Supervisor.start_link([])
    IO.puts("Started Arca.Config supervisor")
    
    # Force a reload to pick up the settings
    {:ok, _} = Arca.Config.reload()
    IO.puts("Reloaded configuration")
  end
end

# Start the simulated application
DependentProject.Application.start()

# Helper to show where files would be created
defmodule PathDebug do
  def print_paths do
    config_file = Arca.Config.Cfg.config_file()
    expanded_path = Path.expand(config_file)
    
    IO.puts("\n=== Path Information ===")
    IO.puts("Current directory: #{File.cwd!()}")
    IO.puts("Config file path from Cfg.config_file(): #{config_file}")
    IO.puts("Expanded config path: #{expanded_path}")
    IO.puts("Is absolute path? #{String.starts_with?(config_file, "/")}")
    IO.puts("Is expanded path absolute? #{String.starts_with?(expanded_path, "/")}")
    
    # Check both possible locations where files might be created
    check_path(expanded_path)
    check_path(config_file)
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

# Print paths to see what's happening
PathDebug.print_paths()

# Now try writing a config value
IO.puts("\n=== Writing config value through ConfigManager ===")
Multiplyer.Ta.Llm.ConfigManager.set_llm_client_type("mock")
IO.puts("Set llm_client_type to 'mock'")

# Check paths again to see what happened
PathDebug.print_paths()

# Try reading it back
IO.puts("\n=== Reading config value ===")
client_type = Multiplyer.Ta.Llm.ConfigManager.get_llm_client_type()
IO.puts("Read llm_client_type: #{client_type}")

# Check for recursive directory creation
IO.puts("\n=== Checking for recursive directory creation ===")
recursive_path = "./.multiplyer/Users/matts/.multiplyer"
if File.exists?(recursive_path) do
  IO.puts("Recursive path exists: YES (BUG!)")
  IO.puts("Contains: #{inspect(File.ls!(recursive_path))}")
else
  IO.puts("Recursive path exists: NO (Good)")
end

# Check both locations where the file might have been written
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
  IO.puts("\nContents of local config file (should not exist):")
  {:ok, content} = File.read(local_config)
  IO.puts(content)
end