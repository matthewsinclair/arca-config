---
verblock: "20250323:v1.0: Claude-assisted - Updated with Arca.Config deployment information"
---
# Arca.Config Deployment Guide

This deployment guide provides instructions for deploying the Arca.Config library in various Elixir application environments. It covers installation, configuration, and integration with other tools and workflows.

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Integration](#integration)
4. [Maintenance](#maintenance)
5. [Upgrading](#upgrading)
6. [Troubleshooting](#troubleshooting)

## Installation

### System Requirements

- Elixir 1.12 or later
- Erlang/OTP 24 or later
- Mix build tool
- A supported operating system (Linux, macOS, Windows)

### Installation Methods

#### Adding to an Elixir Project

Add Arca.Config to your project's dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.5.0"} # Check for the latest version
  ]
end
```

Install the dependency:

```bash
mix deps.get
```

#### Including in Supervision Tree

Add Arca.Config to your application's supervision tree in `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # Your existing children...
    {Arca.Config.Supervisor, []}
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

#### Installation Verification

Verify the installation by creating a simple test:

```elixir
# In your application code or IEx
{:ok, value} = Arca.Config.put("test.key", "test_value")
{:ok, ^value} = Arca.Config.get("test.key")
```

This should successfully set and retrieve a configuration value.

## Configuration

### Environment Variables

Configure Arca.Config behavior using these environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| ARCA_CONFIG_PATH | Directory for configuration files | ~/.arca |
| ARCA_CONFIG_FILE | Name of configuration file | config.json |
| APP_NAME_CONFIG_PATH | App-specific path override | Not set |
| APP_NAME_CONFIG_FILE | App-specific filename override | Not set |

Example configuration in your deployment script or `.bashrc`:

```bash
export ARCA_CONFIG_PATH="/path/to/your/config/dir"
export ARCA_CONFIG_FILE="custom_config.json"
```

### Application Configuration

Configure Arca.Config in your Elixir application configuration files:

```elixir
# In config/config.exs, config/dev.exs, etc.
config :arca_config,
  config_path: "/path/to/config/directory",
  config_file: "custom_config.json",
  parent_app: :your_app_name  # Optional: override parent app name detection
```

### Default Configuration File

Create a default configuration file at one of these locations:

1. The path specified by environment variables
2. `~/.arca/config.json` (in user's home directory)
3. `./.arca/config.json` (in the current directory)

Example configuration file:

```json
{
  "app": {
    "name": "Your Application",
    "version": "1.0.0"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "username": "user"
  },
  "features": {
    "enable_logging": true,
    "debug_mode": false
  }
}
```

## Integration

### Application Integration

#### GenServer Integration

For GenServers that need configuration values:

```elixir
defmodule YourApp.SomeService do
  use GenServer
  
  def init(_) do
    # Get initial config
    {:ok, db_config} = Arca.Config.get("database")
    
    # Subscribe to config changes
    Arca.Config.subscribe("database")
    
    {:ok, %{db_config: db_config}}
  end
  
  def handle_info({:config_updated, ["database"], new_config}, state) do
    # React to configuration change
    {:noreply, %{state | db_config: new_config}}
  end
  
  # Other GenServer callbacks...
end
```

#### Phoenix Integration

For Phoenix applications:

```elixir
# In your endpoint.ex
def init(_key, config) do
  # Load app configuration
  {:ok, app_config} = Arca.Config.get("app")
  
  # Override Phoenix config with values from Arca.Config
  config = 
    config
    |> Keyword.put(:http, [port: app_config["port"] || 4000])
    
  {:ok, config}
end
```

### CI/CD Integration

For CI/CD pipelines, ensure the configuration file is properly set up:

```yaml
# Example GitHub Actions workflow
jobs:
  deploy:
    steps:
      - uses: actions/checkout@v2
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: 1.14.x
          otp-version: 25.x
      
      - name: Create config directory
        run: mkdir -p .arca
        
      - name: Create config file
        run: |
          echo '{
            "app": {
              "name": "YourApp",
              "version": "1.0.0",
              "environment": "production"
            }
          }' > .arca/config.json
          
      # Continue with build and deployment steps
```

### Docker Integration

For Docker deployments:

```dockerfile
FROM elixir:1.14-alpine AS build

# Add your build steps here

FROM alpine:3.16 AS app
COPY --from=build /app/_build/prod/rel/your_app ./

# Set up config directory
RUN mkdir -p /app/config
COPY config.json /app/config/config.json

# Set environment variables
ENV ARCA_CONFIG_PATH=/app/config
ENV ARCA_CONFIG_FILE=config.json

# Run the application
CMD ["/app/bin/your_app", "start"]
```

## Maintenance

### Regular Maintenance Tasks

- Monitor configuration file size (keep it under a reasonable size)
- Review and clean up unused configuration keys
- Ensure proper permissions on configuration files
- Consider encryption for sensitive configuration values

### Backup Practices

- Include configuration files in regular backups
- Version control your configuration files when appropriate
- For sensitive configurations, use environment-specific files that are not committed

## Upgrading

### Upgrading Arca.Config

To upgrade to a newer version:

```elixir
# In mix.exs
def deps do
  [
    {:arca_config, "~> 0.5.0"} # Update version number
  ]
end
```

Then update dependencies:

```bash
mix deps.update arca_config
```

### Migrating Between Versions

When upgrading from a version before 0.5.0:

1. Update supervision tree to use `Arca.Config.Supervisor`
2. Migrate custom change detection to use the callback registration system
3. Update components that watched for changes to use the subscription system
4. Test thoroughly after upgrading

See the [Reference Guide's Upgrade section](./reference_guide.md#upgrading-to-latest-version) for detailed instructions.

## Troubleshooting

### Common Issues

#### Configuration File Not Found

- Verify the configuration file exists at the expected location
- Check environment variables are set correctly
- Ensure your application has read/write permissions to the file

#### ETS Table Issues

```
** (ArgumentError) argument error
    (stdlib 4.0.0) :ets.lookup(Arca.Config.Cache, ["app"])
```

- This typically means the Cache process isn't started
- Ensure Arca.Config.Supervisor is in your application's supervision tree
- Check if ETS owner process is running: `Process.whereis(Arca.Config.Cache)`

#### Subscription Notifications Not Working

- Verify the exact key path is used in the subscription
- Check if Registry process is running: `Process.whereis(Arca.Config.Registry)`
- Ensure the subscriber process properly handles the message format

### Diagnostic Tools

#### Check Process Status

```elixir
# Check if key processes are running
IO.inspect(Process.whereis(Arca.Config.Server), label: "Server")
IO.inspect(Process.whereis(Arca.Config.Cache), label: "Cache")
IO.inspect(Process.whereis(Arca.Config.FileWatcher), label: "FileWatcher")
IO.inspect(Process.whereis(Arca.Config.Registry), label: "Registry")
IO.inspect(Process.whereis(Arca.Config.CallbackRegistry), label: "CallbackRegistry")
```

#### Inspect Current Configuration

```elixir
# Get current configuration state
{:ok, config} = :sys.get_state(Arca.Config.Server)
IO.inspect(config.config, label: "Current Config")
```

#### Check File Watcher State

```elixir
# Check FileWatcher state
watcher_state = :sys.get_state(Arca.Config.FileWatcher)
IO.inspect(watcher_state, label: "FileWatcher State")
```

### Getting Help

If you encounter issues not covered here:

- Check the detailed [API documentation](./reference_guide.md)
- Submit issues to the GitHub repository
- Contact the maintainers through GitHub issues

---

# Context for LLM

This document provides deployment and integration instructions for the Arca.Config library. It covers how to install, configure, maintain, and troubleshoot the library in various Elixir application environments.
