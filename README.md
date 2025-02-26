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

By default, Arca Config looks for a JSON file at `~/.arca/config.json`. You can customize this location by:

1. Setting environment variables:
   - `ARCA_CONFIG_PATH`: Path to the directory containing the config file (default: `~/.arca/`)
   - `ARCA_CONFIG_FILE`: Name of the config file (default: `config.json`)

2. Configuring your application:
   ```elixir
   config :arca_config,
     config_path: "/custom/path/",
     config_file: "custom_config.json"
   ```

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

