# Arca Config

Arca Config is a simple file-based configuration utility for Elixir projects. It provides an easy way to store and retrieve configuration values in a JSON file, with support for nested properties using dot notation.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `arca_config` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arca_config, "~> 0.1.0"}
  ]
end
```

## Usage

### As a Library

```elixir
# Read a configuration value
{:ok, value} = Arca.Config.Cfg.get("database.host")

# Read a configuration value (raises on error)
value = Arca.Config.Cfg.get!("database.host")

# Write a configuration value
{:ok, _} = Arca.Config.Cfg.put("database.host", "localhost")

# Write a configuration value (raises on error)
Arca.Config.Cfg.put!("database.host", "localhost")

# Load the entire configuration
{:ok, config} = Arca.Config.Cfg.load()
```

### As a CLI

Arca Config can also be used as a command-line tool:

```bash
# Get a configuration value
./scripts/cli get database.host

# Set a configuration value
./scripts/cli set database.host localhost

# List all configuration values
./scripts/cli list
```

## Configuration

Arca Config automatically derives its configuration from the parent application. For example, if your application is named `:my_app`:

1. It will first check for a configuration file at `~/.my_app/config.json` in the user's home directory.
2. If no file is found there, it will then look for `./.my_app/config.json` in the current working directory.

This allows for both global user settings and project-specific settings, with the global settings taking precedence.

### Custom Configuration Locations

You can customize the configuration file location in the following ways (in order of precedence):

1. Using generic environment variables (highest priority):
   - `ARCA_CONFIG_PATH`: Path to the directory containing the config file
   - `ARCA_CONFIG_FILE`: Name of the config file

2. Using application-specific environment variables:
   - `MY_APP_CONFIG_PATH`: Path derived from your app name
   - `MY_APP_CONFIG_FILE`: Filename derived from your app name

3. Using application configuration:
   ```elixir
   config :arca_config,
     config_path: "/custom/path/",
     config_file: "custom_config.json"
   ```

4. Default values based on parent application (lowest priority):
   - Default path: `~/.{app_name}/`
   - Default file: `config.json`

This auto-configuration feature means you don't need duplicate configuration across different applications, while maintaining backward compatibility with existing applications.

## Development

```bash
# Run tests
./scripts/test

# Run IEx with the project loaded
./scripts/iex

# Use the CLI
./scripts/cli
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
mix docs
```

## License

MIT

