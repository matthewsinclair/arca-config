---
verblock: "20250323:v1.0: Claude-assisted - Updated with Arca.Config user guide"
---
# Arca.Config User Guide

This user guide provides task-oriented instructions for using the Arca.Config library. It explains how to accomplish common tasks and provides workflow guidance.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Getting Started](#getting-started)
4. [Common Tasks](#common-tasks)
5. [Advanced Usage](#advanced-usage)
6. [Troubleshooting](#troubleshooting)

## Introduction

Arca.Config is an Elixir library for managing application configuration with features for file-based persistence, runtime updates, change notifications, and automatic file watching.

### Purpose

Arca.Config solves common configuration management problems in Elixir applications:

- Storing configuration in a persistent, human-readable file format
- Accessing configuration via a simple API with dot notation
- Updating configuration at runtime and persisting changes
- Detecting external changes to configuration files
- Notifying application components when configuration changes

### Core Concepts

- **Configuration File**: A JSON file containing application settings
- **Dot Notation**: Accessing nested configuration using period-separated paths
- **Subscriptions**: Mechanisms to receive notifications when configuration changes
- **Callbacks**: Functions called when configuration changes
- **File Watching**: Automatic detection of external file changes

## Installation

### Prerequisites

- Elixir 1.12 or later
- Erlang/OTP 24 or later
- Mix build tool

### Installation Steps

1. Add Arca.Config to your project dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.5.0"} # Check for the latest version
  ]
end
```

2. Install dependencies:

```bash
mix deps.get
```

3. Ensure Arca.Config is included in your application supervision tree:

```elixir
# In your application.ex file
def start(_type, _args) do
  children = [
    # Other children...
    {Arca.Config.Supervisor, []}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Getting Started

### First Steps

After installing Arca.Config, create a basic configuration file:

1. Create a `.arca` directory in your project root:

```bash
mkdir .arca
```

2. Create a basic `config.json` file:

```json
{
  "app": {
    "name": "MyApp",
    "version": "1.0.0"
  },
  "features": {
    "enable_logging": true,
    "debug_mode": false
  }
}
```

3. Access your configuration in your application:

```elixir
# Get a configuration value
{:ok, app_name} = Arca.Config.get("app.name")
# => {:ok, "MyApp"}

# Update a configuration value
{:ok, _} = Arca.Config.put("features.debug_mode", true)
```

### Basic Workflow

The typical workflow with Arca.Config is:

1. Define default configuration in a JSON file
2. Access configuration values in your application using `Arca.Config.get/1`
3. Update configuration at runtime using `Arca.Config.put/2`
4. Handle configuration changes by subscribing to specific keys

## Common Tasks

### Reading Configuration Values

```elixir
# Get a value with standard error handling
case Arca.Config.get("database.host") do
  {:ok, host} -> 
    # Use the host value
  {:error, reason} ->
    # Handle the error
end

# Get a value with exceptions for errors
host = Arca.Config.get!("database.host")

# Get a value with a default
{:ok, port} = Arca.Config.get("database.port", 5432)

# Check if a key exists
if Arca.Config.has_key?("features.new_ui") do
  # Use the feature
end

# Get nested values using lists
{:ok, username} = Arca.Config.get([:database, :credentials, :username])
```

### Writing Configuration Values

```elixir
# Update a value with standard error handling
case Arca.Config.put("app.version", "1.1.0") do
  {:ok, _} -> 
    # Handle success
  {:error, reason} ->
    # Handle error
end

# Update a value with exceptions
Arca.Config.put!("features.enable_logging", false)

# Update nested values using lists
Arca.Config.put([:database, :credentials], %{
  "username" => "new_user",
  "password" => "new_password"
})
```

### Reloading Configuration

```elixir
# Reload configuration from disk
{:ok, _} = Arca.Config.reload()
```

## Advanced Usage

### Subscribing to Configuration Changes

Subscribe to be notified when specific configuration keys change:

```elixir
# In a GenServer or other process

# Initialize with subscription
def init(args) do
  # Subscribe to configuration changes
  Arca.Config.subscribe("features.debug_mode")
  {:ok, %{debug_mode: false}}
end

# Handle configuration update messages
def handle_info({:config_updated, key_path, new_value}, state) do
  case key_path do
    ["features", "debug_mode"] ->
      IO.puts("Debug mode changed to: #{inspect(new_value)}")
      {:noreply, %{state | debug_mode: new_value}}
    _ ->
      {:noreply, state}
  end
end

# When done, unsubscribe
def terminate(_reason, _state) do
  Arca.Config.unsubscribe("features.debug_mode")
  :ok
end
```

### Registering Change Callbacks

Register callback functions to be called when any configuration changes:

```elixir
# Register a callback when your application starts
def start_link(opts) do
  # Start your process
  pid = GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  
  # Register a callback for configuration changes
  Arca.Config.register_change_callback(__MODULE__, fn config ->
    GenServer.cast(__MODULE__, {:config_updated, config})
  end)
  
  {:ok, pid}
end

# Handle the callback in your GenServer
def handle_cast({:config_updated, config}, state) do
  # React to configuration changes
  new_state = update_state_based_on_config(state, config)
  {:noreply, new_state}
end

# Unregister when shutting down
def terminate(_reason, _state) do
  Arca.Config.unregister_change_callback(__MODULE__)
  :ok
end
```

### Custom Configuration Paths

Specify custom paths for configuration files:

```elixir
# Using environment variables
System.put_env("ARCA_CONFIG_PATH", "/path/to/config/directory")
System.put_env("ARCA_CONFIG_FILE", "my_custom_config.json")

# Using application environment in config.exs
config :arca_config,
  config_domain: :your_app_name,  # Override config domain detection
  config_path: "/path/to/config/directory",
  config_file: "my_custom_config.json"
```

## Troubleshooting

### Common Issues

1. **Configuration Not Found**
   - Check that the configuration file exists in one of the expected locations
   - Verify environment variables if using custom paths
   - Ensure JSON syntax is valid

2. **Unable to Update Configuration**
   - Check file permissions for the configuration file
   - Verify the process has write access to the directory
   - Check disk space

3. **Subscription Notifications Not Working**
   - Ensure exact key path is used in the subscription
   - Verify the process is properly handling the message format
   - Check Registry process is running

4. **File Watcher Not Detecting Changes**
   - Ensure changes are saved to disk
   - Check file timestamps are changing
   - Verify FileWatcher process is running

### Getting Help

For additional help:

- Check the reference guide for detailed API documentation
- Visit the GitHub repository for the latest updates
- Use GitHub issues to report bugs or request features

---

# Context for LLM

This document provides a user guide for the Arca.Config library, with task-oriented instructions for common operations. The guide is focused on helping developers effectively use the configuration management features, with practical examples for each operation.
