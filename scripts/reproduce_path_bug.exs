#!/usr/bin/env elixir

# reproduce_path_bug.exs
#
# This script reproduces and demonstrates the path handling bug in Arca.Config

# Ensure the app is compiled and available
Mix.install([
  {:jason, "~> 1.2"}
])

# Set up the environment
System.put_env("MULTIPLYER_CONFIG_PATH", "/Users/matts/.multiplyer")
System.put_env("MULTIPLYER_CONFIG_FILE", "config.json")

# Load the app
Code.require_file("lib/arca_config.ex")
Code.require_file("lib/config/cfg.ex")
Code.require_file("lib/config/server.ex")
Code.require_file("lib/config/cache.ex")
Code.require_file("lib/config/supervisor.ex")
Code.require_file("lib/config/file_watcher.ex")
Code.require_file("lib/config/init_helper.ex")
Code.require_file("lib/config/map.ex")

# Helper function to inspect paths for debugging
defmodule PathDebug do
  def print_paths do
    config_file = Arca.Config.Cfg.config_file()
    expanded_path = Path.expand(config_file)
    
    IO.puts("Current directory: #{File.cwd!()}")
    IO.puts("Config file path: #{config_file}")
    IO.puts("Expanded config path: #{expanded_path}")
    IO.puts("Is absolute path? #{String.starts_with?(config_file, "/")}")
    IO.puts("Is expanded path absolute? #{String.starts_with?(expanded_path, "/")}")
  end
end

# First check the paths
IO.puts("\n=== Path Information ===")
PathDebug.print_paths()

# Now try writing a config value
IO.puts("\n=== Attempting to write config ===")
Application.put_env(:arca_config, :config_domain, :multiplyer)
config_file_path = Arca.Config.Cfg.config_file() |> Path.expand()
IO.puts("Config file should be at: #{config_file_path}")

# Get the current directory structure to show where files are being created
IO.puts("\n=== Current directory before writing ===")
IO.inspect(File.ls!("."))

# Start the application
{:ok, _pid} = Arca.Config.Supervisor.start_link([])

# Write a config value
IO.puts("\n=== Writing config value ===")
Arca.Config.put("llm_client_type", "mock")

# Check what happened in the current directory after writing
IO.puts("\n=== Current directory after writing ===")
IO.inspect(File.ls!("."))

# Check if the .multiplyer directory was created in the local directory
if File.exists?("./.multiplyer") do
  IO.puts("\n=== Local .multiplyer directory was created (BUG!) ===")
  IO.puts("Contents of ./.multiplyer:")
  case File.ls!("./.multiplyer") do
    [] -> IO.puts("  (empty)")
    contents -> IO.inspect(contents, label: "  Contents")
  end
  
  # Check if we have a recursive structure
  recursive_path = "./.multiplyer/Users/matts/.multiplyer"
  if File.exists?(recursive_path) do
    IO.puts("\n=== Recursive directory structure created (BUG!) ===")
    IO.puts("Contents of #{recursive_path}:")
    case File.ls!(recursive_path) do
      [] -> IO.puts("  (empty)")
      contents -> IO.inspect(contents, label: "  Contents")
    end
  end
end

# Check the actual target location (to verify if anything was written there)
actual_target = "/Users/matts/.multiplyer"
if File.exists?(actual_target) do
  IO.puts("\n=== Contents of the actual target directory ===")
  IO.puts("Contents of #{actual_target}:")
  case File.ls!(actual_target) do
    [] -> IO.puts("  (empty)")
    contents -> IO.inspect(contents, label: "  Contents")
  end
  
  config_path = Path.join([actual_target, "config.json"])
  if File.exists?(config_path) do
    IO.puts("\nContents of the actual config file:")
    IO.puts(File.read!(config_path))
  end
end