---
verblock: "20250323:v1.0: Claude-assisted - Updated with Arca.Config reference information"
---
# Arca.Config Reference Guide

This reference guide provides comprehensive information about the Arca.Config library. Unlike the task-oriented User Guide, this reference guide serves as a complete reference for all aspects of the system.

## Table of Contents

1. [API Reference](#api-reference)
2. [Configuration Options](#configuration-options)
3. [Component Architecture](#component-architecture)
4. [Registry Integration](#registry-integration)
5. [Persistence Model](#persistence-model)
6. [Upgrading to Latest Version](#upgrading-to-latest-version)
7. [Best Practices](#best-practices)
8. [Concepts and Terminology](#concepts-and-terminology)

## API Reference

### Core API Functions

#### `get/1`, `get/2`

Retrieves a configuration value by key path.

**Usage:**

```elixir
Arca.Config.get(key_path)
Arca.Config.get(key_path, default)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)
- `default`: Value to return if key doesn't exist (optional)

**Returns:**

- `{:ok, value}` if the key exists
- `{:error, reason}` if the key doesn't exist (without default)
- `{:ok, default}` if key doesn't exist (with default)

**Example:**

```elixir
{:ok, host} = Arca.Config.get("database.host")
{:ok, port} = Arca.Config.get([:database, :port], 5432)
```

#### `get!/1`

Retrieves a configuration value by key path or raises an error.

**Usage:**

```elixir
Arca.Config.get!(key_path)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)

**Returns:**

- The value if the key exists

**Raises:**

- `RuntimeError` if the key doesn't exist

**Example:**

```elixir
host = Arca.Config.get!("database.host")
```

#### `put/2`

Updates a configuration value.

**Usage:**

```elixir
Arca.Config.put(key_path, value)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)
- `value`: The new value to set (required)

**Returns:**

- `{:ok, value}` if the update was successful
- `{:error, reason}` if an error occurred

**Example:**

```elixir
{:ok, _} = Arca.Config.put("features.logging", true)
```

#### `put!/2`

Updates a configuration value or raises an error.

**Usage:**

```elixir
Arca.Config.put!(key_path, value)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)
- `value`: The new value to set (required)

**Returns:**

- The value if the update was successful

**Raises:**

- `RuntimeError` if an error occurred

**Example:**

```elixir
Arca.Config.put!("app.version", "1.1.0")
```

#### `reload/0`

Reloads the configuration from disk.

**Usage:**

```elixir
Arca.Config.reload()
```

**Returns:**

- `{:ok, config}` with the loaded configuration if successful
- `{:error, reason}` if an error occurred

**Example:**

```elixir
{:ok, _} = Arca.Config.reload()
```

#### `subscribe/1`

Subscribes to changes to a specific configuration key.

**Usage:**

```elixir
Arca.Config.subscribe(key_path)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)

**Returns:**

- `{:ok, :subscribed}` if the subscription was successful

**Example:**

```elixir
{:ok, :subscribed} = Arca.Config.subscribe("database.host")
```

#### `unsubscribe/1`

Unsubscribes from changes to a specific configuration key.

**Usage:**

```elixir
Arca.Config.unsubscribe(key_path)
```

**Parameters:**

- `key_path`: A dot-separated string or list representing the path (required)

**Returns:**

- `{:ok, :unsubscribed}` if the unsubscription was successful

**Example:**

```elixir
{:ok, :unsubscribed} = Arca.Config.unsubscribe("database.host")
```

#### `register_change_callback/2`

Registers a callback for configuration changes.

**Usage:**

```elixir
Arca.Config.register_change_callback(callback_id, callback_fn)
```

**Parameters:**

- `callback_id`: Identifier for the callback (required)
- `callback_fn`: Function that takes the entire config map (required)

**Returns:**

- `{:ok, :registered}` if the registration was successful

**Example:**

```elixir
{:ok, :registered} = Arca.Config.register_change_callback(:my_component, fn config ->
  IO.puts("Config changed: #{inspect(config)}")
end)
```

#### `unregister_change_callback/1`

Unregisters a previously registered callback.

**Usage:**

```elixir
Arca.Config.unregister_change_callback(callback_id)
```

**Parameters:**

- `callback_id`: The identifier of the callback to unregister (required)

**Returns:**

- `{:ok, :unregistered}` if the unregistration was successful

**Example:**

```elixir
{:ok, :unregistered} = Arca.Config.unregister_change_callback(:my_component)
```

## Configuration Options

### Environment Variables

Configuration options can be controlled through environment variables:

| Variable             | Purpose                              | Default     |
|----------------------|--------------------------------------|-------------|
| ARCA_CONFIG_PATH     | Directory containing the config file | ~/.arca     |
| ARCA_CONFIG_FILE     | Name of the config file              | config.json |
| APP_NAME_CONFIG_PATH | App-specific config path override    | None        |
| APP_NAME_CONFIG_FILE | App-specific config file override    | None        |

### Application Configuration

In your `config.exs` or other config files:

```elixir
config :arca_config,
  config_path: "/path/to/config/directory",
  config_file: "custom_config.json",
  config_domain: :your_app_name  # Override config domain detection
```

### File Format

Arca.Config uses JSON format for configuration files:

```json
{
  "app": {
    "name": "MyApp",
    "version": "1.0.0"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "credentials": {
      "username": "user",
      "password": "password"
    }
  },
  "features": {
    "logging": true,
    "metrics": false
  }
}
```

## Component Architecture

Arca.Config consists of several key components:

1. **Public API** (`Arca.Config`): Provides the external interface
2. **Supervisor** (`Arca.Config.Supervisor`): Manages all processes
3. **Server** (`Arca.Config.Server`): Manages configuration state
4. **Cache** (`Arca.Config.Cache`): ETS-based caching layer
5. **FileWatcher** (`Arca.Config.FileWatcher`): Monitors config file changes
6. **Registry**: For change subscriptions
7. **CallbackRegistry**: For change callbacks

## Registry Integration

Arca.Config uses two Registry instances:

### Subscription Registry

The `Arca.Config.Registry` is used for key-specific subscriptions:

- Processes register for specific key paths
- When a key changes, all subscribers receive a message
- Messages are in the format `{:config_updated, key_path, new_value}`

### Callback Registry

The `Arca.Config.CallbackRegistry` is used for whole-config callbacks:

- Functions register with a unique ID
- When configuration changes externally, all callbacks are called
- Callbacks receive the entire configuration map
- Used for broader application-level reactions to config changes

## Persistence Model

### File Storage

- Configuration is stored in a JSON file
- The file is read at application startup
- Changes made through the API are written to disk asynchronously
- External changes are detected by the FileWatcher

### Write Process

1. Application calls `put/2`
2. Server updates in-memory config
3. Server generates a unique token for the write
4. FileWatcher registers the token
5. File is written asynchronously by a Task
6. When FileWatcher detects the change, it ignores it because of the token

### External Change Detection

1. FileWatcher periodically checks the config file's timestamp
2. If a change is detected without a matching token:
   - Server reloads the configuration
   - Cache is cleared and rebuilt
   - Callbacks are notified

## Upgrading to Latest Version

### Upgrade Steps

To upgrade to the latest version of Arca.Config:

1. Update the dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.5.0"}, # Update to the latest version
    # Other dependencies...
  ]
end
```

2. Update your dependencies:

```bash
mix deps.get
mix deps.update arca_config
```

3. Run your tests to verify compatibility:

```bash
mix test
```

### Supervision Tree Changes

If your application manually starts Arca.Config, update the supervision tree:

```elixir
# Previous (older versions)
children = [
  {Arca.Config, []} # or some variant of this
]

# New version (0.5.0+)
children = [
  {Arca.Config.Supervisor, []}
]
```

### Change Detection Upgrades

If your application had custom code to detect configuration changes, replace it with the new callback system:

```elixir
# Register a callback for configuration changes
Arca.Config.register_change_callback(:my_component, fn config ->
  # Handle configuration changes
  IO.puts("Configuration changed")
  update_component_with_new_config(config)
end)

# Later, when no longer needed
Arca.Config.unregister_change_callback(:my_component)
```

### Subscription Implementation

For components that need to watch for specific key changes:

```elixir
# Subscribe to specific key changes
Arca.Config.subscribe("path.to.specific.key")

# In your process, handle the notification messages
def handle_info({:config_updated, key_path, new_value}, state) do
  # React to the specific key change
  {:noreply, update_state(state, key_path, new_value)}
end

# When no longer needed
Arca.Config.unsubscribe("path.to.specific.key")
```

### API Compatibility

The basic API (`get/1`, `get!/1`, `put/2`, `put!/2`, and `reload/0`) remains unchanged, so existing code using these functions will continue to work.

### Claude Code Upgrade Prompt

To upgrade projects using Arca.Config with Claude Code, you can use the prompt from [ST0001_upgrade_prompt.md](../../prj/st/ST0001_upgrade_prompt.md), which provides detailed instructions for automated upgrades.

## Best Practices

### Configuration Structure

- Use descriptive key names
- Group related configuration in nested objects
- Keep sensitive information separate and consider environment variables
- Avoid deep nesting beyond 3-4 levels
- Use consistent naming conventions

### Performance Optimization

- Cache frequently accessed values at application startup
- Batch configuration updates when possible
- Keep callback functions lightweight
- Unsubscribe from notifications when no longer needed
- Consider the overhead of file watching in development environments

### Error Handling

- Use pattern matching with `{:ok, value}` and `{:error, reason}` tuples
- Provide meaningful default values for optional configuration
- Validate configuration at startup
- Handle missing configuration gracefully
- Use exception-raising functions (`get!/1`, `put!/2`) only when appropriate

## Upgrading to Latest Version

### Upgrade Steps

To upgrade to the latest version of Arca.Config:

1. Update the dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.5.0"}, # Update to the latest version
    # Other dependencies...
  ]
end
```

2. Update your dependencies:

```bash
mix deps.get
mix deps.update arca_config
```

3. Run your tests to verify compatibility:

```bash
mix test
```

### Supervision Tree Changes

If your application manually starts Arca.Config, update the supervision tree:

```elixir
# Previous (older versions)
children = [
  {Arca.Config, []} # or some variant of this
]

# New version (0.5.0+)
children = [
  {Arca.Config.Supervisor, []}
]
```

### Change Detection Upgrades

If your application had custom code to detect configuration changes, replace it with the new callback system:

```elixir
# Register a callback for configuration changes
Arca.Config.register_change_callback(:my_component, fn config ->
  # Handle configuration changes
  IO.puts("Configuration changed")
  update_component_with_new_config(config)
end)

# Later, when no longer needed
Arca.Config.unregister_change_callback(:my_component)
```

### Subscription Implementation

For components that need to watch for specific key changes:

```elixir
# Subscribe to specific key changes
Arca.Config.subscribe("path.to.specific.key")

# In your process, handle the notification messages
def handle_info({:config_updated, key_path, new_value}, state) do
  # React to the specific key change
  {:noreply, update_state(state, key_path, new_value)}
end

# When no longer needed
Arca.Config.unsubscribe("path.to.specific.key")
```

### API Compatibility

The basic API (`get/1`, `get!/1`, `put/2`, `put!/2`, and `reload/0`) remains unchanged, so existing code using these functions will continue to work.

### Claude Code Upgrade Prompt

To upgrade projects using Arca.Config with Claude Code, you can use the prompt from [ST0001_upgrade_prompt.md](../../prj/st/ST0001_upgrade_prompt.md), which provides detailed instructions for automated upgrades.

## Concepts and Terminology

| Term | Definition |
|------|------------|
| Configuration | A set of key-value pairs that control application behavior |
| JSON | JavaScript Object Notation, the file format used for configuration storage |
| Dot Notation | Accessing nested configuration using period-separated paths (e.g., "database.host") |
| Registry | Elixir's built-in key-value process registry used for subscriptions |
| Subscription | A mechanism to receive notifications when specific configuration keys change |
| Callback | A function called when configuration changes occur |
| File Watcher | A process that monitors configuration files for external changes |
| ETS | Erlang Term Storage, used for caching configuration values |
| Asynchronous Writes | Background operations that don't block the server |
| Token | A unique identifier for tracking write operations to avoid notification loops |

---

# Context for LLM

This document provides a comprehensive reference guide for the Arca.Config library, including detailed API information, configuration options, upgrade instructions, and technical concepts. This reference is aimed at developers who need in-depth understanding of the library's capabilities and implementation details.
