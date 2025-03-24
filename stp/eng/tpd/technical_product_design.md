---
verblock: "20250323:v0.2: Claude-assisted - Updated with Arca.Config design"
---

## Preamble to Claude

This document is a Technical Product Design (TPD) for the Arca.Config system. When processing this document, please understand:

1. This is a comprehensive technical specification for the system
2. The document contains:
   - System architecture and design principles
   - Requirements and constraints
   - Implementation details and plans
   - Future development roadmap

3. Arca.Config is an Elixir library for managing application configuration with features for file-based persistence, runtime updates, change notifications, and automatic file watching.

# Arca.Config Technical Product Design

This document serves as the central index for the Technical Product Design (TPD) of the Arca.Config system. The TPD details the architecture, implementation, and roadmap for the system.

## Table of Contents

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Architecture](#architecture)
4. [Component Design](#component-design)
5. [Data Flow](#data-flow)
6. [Registry Integration](#registry-integration)
7. [Error Handling](#error-handling)
8. [Performance Considerations](#performance-considerations)
9. [Upgrade Path](#upgrade-path)

## Introduction

Arca.Config is a configuration management library for Elixir applications. It provides a robust, reliable, and flexible way to manage application configuration with file persistence and change notifications.

## Requirements

1. Store and retrieve runtime configuration parameters in a JSON file that is automatically loaded at runtime
2. Allow applications to write back config changes that persist to the config file
3. Provide a simple dictionary lookup interface to access configuration data
4. Support dot notation for accessing nested configuration values
5. Detect changes to the configuration file made outside the application
6. Provide a notification system for configuration changes
7. Allow registering callbacks for reacting to configuration changes
8. Support asynchronous file writing to avoid blocking
9. Maintain backward compatibility with existing configuration methods

## Architecture

Arca.Config follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│                   Public API (Arca.Config)              │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────┐
│                           │                             │
│  ┌───────────────┐    ┌───▼───────────┐    ┌───────────┐│
│  │ File Watcher  │◄──►│    Server     │◄───►  Cache    ││
│  └───────────────┘    └───────────────┘    └───────────┘│
│                             │                           │
│                      ┌──────┴───────┐                   │
│                      │              │                   │
│               ┌──────▼─────┐  ┌─────▼──────┐            │
│               │  Registry  │  │ Callbacks  │            │
│               └────────────┘  └────────────┘            │
│                                                         │
│                       Core Components                   │
└─────────────────────────────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────┐
│                 Configuration Storage                   │
│                                                         │
│  ┌───────────────────┐        ┌────────────────────┐    │
│  │  In-Memory Cache  │        │  Filesystem (JSON) │    │
│  └───────────────────┘        └────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Key Components

1. **Arca.Config**: Public API module that exposes the configuration interface
2. **Arca.Config.Supervisor**: Supervises all components
3. **Arca.Config.Server**: GenServer managing configuration state
4. **Arca.Config.Cache**: ETS-based caching layer
5. **Arca.Config.FileWatcher**: Monitors config files for external changes
6. **Arca.Config.Registry**: Registry for change subscriptions
7. **Arca.Config.CallbackRegistry**: Registry for change callback registrations

## Component Design

### Public API (Arca.Config)

The API provides simple functions for accessing and modifying configuration:

- `get/1`: Get a configuration value by key
- `get!/1`: Get a configuration value or raise if not found
- `put/2`: Update a configuration value
- `put!/2`: Update a configuration value or raise if error
- `reload/0`: Reload configuration from disk
- `subscribe/1`: Subscribe to changes on a specific key
- `unsubscribe/1`: Unsubscribe from changes
- `register_change_callback/2`: Register a callback function for changes
- `unregister_change_callback/1`: Unregister a callback function

### Server (Arca.Config.Server)

The Server component:

- Maintains the in-memory configuration state
- Coordinates between components
- Handles configuration updates
- Manages notification dispatching
- Coordinates file reading/writing

### Cache (Arca.Config.Cache)

The Cache component:

- Uses ETS for fast key-value storage
- Caches configuration values for quick access
- Maintains path-based invalidation for nested values
- Provides resilience against process failures

### FileWatcher (Arca.Config.FileWatcher)

The FileWatcher component:

- Periodically checks configuration file timestamps
- Detects changes made outside the application
- Uses a token system to avoid notification loops
- Triggers reload and notification on external changes

## Data Flow

### Configuration Loading and Reading

1. Application requests a configuration value via `Arca.Config.get/1`
2. The request is forwarded to `Arca.Config.Cache`
3. If the value is in cache, it's returned immediately
4. If not, `Arca.Config.Server` retrieves the value from the in-memory configuration
5. The value is cached and returned

### Configuration Updates

1. Application updates a configuration value via `Arca.Config.put/2`
2. Update is forwarded to `Arca.Config.Server`
3. Server updates the in-memory configuration
4. Cache is updated for the changed key and ancestors
5. Server initiates an asynchronous file write with a unique token
6. FileWatcher registers the token to prevent self-notification
7. Subscribers to the changed keys are notified asynchronously

### External Change Detection

1. `Arca.Config.FileWatcher` periodically checks the config file timestamp
2. When a change is detected (and not from a registered token):
   a. The server reloads the configuration
   b. Cache is cleared and repopulated
   c. External callbacks are notified of the change

## Registry Integration

Arca.Config uses two Registry instances:

1. **Arca.Config.Registry**: For subscribing to changes to specific configuration keys
2. **Arca.Config.CallbackRegistry**: For registering callback functions to be notified when configuration changes

### Configuration Domain Detection

Arca.Config automatically detects the application's config domain (usually the OTP application name). This discovery works by:

1. Examining the process hierarchy to find the caller's OTP application
2. Falling back to an explicitly configured domain with `config :arca_config, config_domain: :your_app_name`
3. Using `:arca_config` as the final fallback

The config domain is used to generate environment variable names and default configuration paths.

### Subscription Model

The subscription model uses the Registry's duplicate key feature:

```elixir
# Register for changes to a specific key
Registry.register(Arca.Config.Registry, key_path, nil)

# When a change happens, all subscribers are notified
Registry.dispatch(Arca.Config.Registry, key_path, fn entries ->
  for {pid, _} <- entries do
    send(pid, {:config_updated, key_path, value})
  end
end)
```

### Callback Model

The callback model also uses the Registry:

```elixir
# Register a callback
Registry.register(Arca.Config.CallbackRegistry, :config_change, {callback_id, callback_fn})

# When configuration changes externally, all callbacks are notified
Registry.dispatch(Arca.Config.CallbackRegistry, :config_change, fn entries ->
  for {process_pid, {id, callback_fn}} <- entries do
    callback_fn.(config)
  end
end)
```

## Error Handling

Arca.Config uses a railway-oriented programming approach with `{:ok, result}` and `{:error, reason}` tuples. All public functions have both a standard version returning these tuples and a bang (!) version that raises exceptions on errors.

Error handling strategies include:

1. Graceful degradation with fallbacks
2. Clear error messages
3. Process isolation to prevent cascading failures
4. Supervision for automatic process recovery

## Performance Considerations

1. **ETS-based caching**: Fast access to frequently used config values
2. **Asynchronous writes**: File writes don't block the server
3. **Efficient change notifications**: Only affected keys trigger notifications
4. **Lazy loading**: Only load what's needed when possible

## Upgrade Path

When upgrading from previous versions of Arca.Config:

1. Update the library dependency
2. Migrate any custom change detection to use the new callback registration system
3. Update supervision tree if manually starting Arca.Config

For a detailed upgrade guide, see the [Upgrade Prompt](../../prj/st/ST0001_upgrade_prompt.md)

## Handling Missing Configuration Files

When using Arca.Config, you might encounter an issue where the library fails to properly handle non-existent configuration files, resulting in errors like:

```
Failed to load configuration: Failed to load config file: enoent
```

### The Problem

The issue occurs in the `Arca.Config.Server` module's `handle_info(:initialize_config, state)` function, which doesn't properly initialize the config field with an empty map when a configuration file doesn't exist yet.

### The Solution

There are two approaches to fix this issue:

#### 1. Using the InitHelper Module

The simplest solution is to use the `Arca.Config.InitHelper` module, which provides functions to ensure your configuration directory and files exist before the Arca.Config system tries to load them.

Here's an example of how to use it in your Application module:

```elixir
defmodule MyApp.Application do
  use Application
  
  require Logger
  
  @impl true
  def start(_type, _args) do
    # Initialize config before starting the rest of your application
    case initialize_config() do
      {:ok, config_path} ->
        Logger.info("Configuration initialized at: #{config_path}")
        
        # Continue with your regular application startup
        children = [
          # Your supervisors and workers here
        ]
        
        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
        
      {:error, reason} ->
        Logger.error("Failed to initialize configuration: #{reason}")
        {:error, reason}
    end
  end
  
  defp initialize_config do
    # Define your default configuration
    initial_config = %{
      "app" => %{
        "name" => "MyApp",
        "version" => "1.0.0"
      },
      # Other default settings
    }
    
    # Initialize with your app name and defaults
    Arca.Config.InitHelper.init_config(:my_app, initial_config)
  end
end
```

#### 2. Setup a Default Config Location

If you want to use a standard location like `~/.myapp/config.json`, you can use the helper function for this common pattern:

```elixir
defmodule MyApp.Application do
  use Application
  
  @impl true
  def start(_type, _args) do
    # Set up default config in ~/.myapp/config.json
    {:ok, config_path} = Arca.Config.InitHelper.setup_default_config(:my_app, %{
      "initialized" => true,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
    
    # Continue with application startup
    # ...
  end
end
```

#### How It Works

The helper functions:

1. Create the configuration directory if it doesn't exist
2. Create a minimal configuration file if none exists
3. Set the proper environment variables for Arca.Config

This ensures that by the time Arca.Config tries to load the configuration, the file exists and can be loaded successfully, even if it's just an empty JSON object.

## Environment Variable Overrides

Arca.Config supports overriding configuration values through environment variables at application startup. This feature is particularly useful for deployment scenarios where you need different configuration values in different environments.

### How It Works

1. When Arca.Config starts, it checks for environment variables matching a specific pattern
2. Variables with the pattern `APP_NAME_CONFIG_OVERRIDE_KEY=value` are automatically applied as configuration overrides
3. These overrides are written to the configuration file, ensuring consistency between the file and the running configuration
4. Values are automatically converted to appropriate types (strings, numbers, booleans, JSON objects/arrays)

### Configuration Pattern

Environment variables must follow this pattern:

```
APP_NAME_CONFIG_OVERRIDE_SECTION_KEY=value
```

Where:
- `APP_NAME` is your application name in uppercase
- `SECTION_KEY` is the configuration path with dots replaced by underscores

### Example Overrides

```bash
# Override database host
export MY_APP_CONFIG_OVERRIDE_DATABASE_HOST=production-db.example.com

# Override server port (automatically converted to integer)
export MY_APP_CONFIG_OVERRIDE_SERVER_PORT=5432

# Enable debug mode (automatically converted to boolean)
export MY_APP_CONFIG_OVERRIDE_DEBUG_ENABLED=true

# Set a complex value (automatically parsed as JSON)
export MY_APP_CONFIG_OVERRIDE_FEATURE_FLAGS='{"new_ui": true, "beta_features": false}'
```

### Implementation Details

The override mechanism:

1. Runs during application startup in the `Arca.Config.start/2` function
2. Uses the existing configuration writing mechanisms to ensure consistency
3. Converts values to appropriate types based on string pattern recognition
4. Logs each override that is applied
5. Preserves existing configuration values not being overridden

This approach ensures that configuration is consistent regardless of how it was initially set, while providing flexibility for environment-specific deployment configurations.

## Path Handling

Arca.Config takes a special approach to path handling to balance precision with usability:

### Environment Variable Path Preservation

When paths are specified via environment variables (e.g., `MY_APP_CONFIG_PATH=/tmp/`), Arca.Config preserves the exact format, including trailing slashes. This ensures compatibility with tools and scripts that expect precise path formats.

```elixir
# When set from environment variable
System.put_env("MY_APP_CONFIG_PATH", "/tmp/")
Arca.Config.Cfg.config_pathname() # Returns "/tmp/" with trailing slash preserved

# When from application config or defaults
Application.put_env(:arca_config, :config_path, "/tmp/")
Arca.Config.Cfg.config_pathname() # Returns "/tmp" with path expanded
```

### Path Expansion

For non-environment variable paths (from application configuration or defaults), Arca.Config uses `Path.expand/1` to normalize paths, which:
- Resolves relative paths against the current working directory
- Expands `~` to the user's home directory
- Removes trailing slashes for consistency
- Normalizes path separators

This dual approach ensures both precision for explicit environment variables and normalization for other configuration sources.
