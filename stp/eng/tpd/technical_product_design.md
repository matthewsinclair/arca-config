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
