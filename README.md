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

## Setup

**IMPORTANT**: Starting from this version, Arca.Config requires OTP start phases for proper initialization.

### 1. Add dependency to mix.exs

```elixir
def deps do
  [
    {:arca_config, "~> 0.2.0"}
  ]
end
```

### 2. Configure start phases in mix.exs

```elixir
def application do
  [
    extra_applications: [:logger],
    start_phases: [load_config: []]
  ]
end
```

### 3. Set config domain and implement start phase in your Application module

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # REQUIRED: Set the config domain before starting supervision tree
    Application.put_env(:arca_config, :config_domain, :my_app)
    
    children = [
      # Your supervisors and workers here
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def start_phase(:load_config, _start_type, _phase_args) do
    # REQUIRED: Load configuration during start phase
    Arca.Config.load_config_phase()
  end
end
```

## Usage

### As a Library

```elixir
# Read a configuration value
{:ok, value} = Arca.Config.get("database.host")

# Read a configuration value (raises on error)
value = Arca.Config.get!("database.host")

# Write a configuration value
{:ok, _} = Arca.Config.put("database.host", "localhost")

# Write a configuration value (raises on error)
Arca.Config.put!("database.host", "localhost")

# Reload configuration from disk
{:ok, config} = Arca.Config.reload()
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

Arca Config automatically derives its configuration from the config domain. For example, if your application is named `:my_app`:

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
     config_domain: :your_app_name,  # Override config domain detection
     config_path: "/custom/path/",
     config_file: "custom_config.json"
   ```

4. Default values based on config domain (lowest priority):
   - Default path: `~/.{app_name}/`
   - Default file: `config.json`

This auto-configuration feature means you don't need duplicate configuration across different applications, while maintaining backward compatibility with existing applications.

### Environment Variables (.env file)

Arca.Config automatically loads environment variables from `config/.env` file in development and test environments. This makes it easy to set configuration without manually sourcing files.

Create a `config/.env` file in your project:

```bash
# config/.env
ARCA_CONFIG_CONFIG_PATH=.arca_config
ARCA_CONFIG_CONFIG_FILE=config.json

# Your custom environment variables
DATABASE_URL=postgres://localhost/myapp_dev
API_KEY=development_key_123
```

The .env file is automatically loaded when you run:
- `mix test`
- `iex -S mix`
- `mix run`
- Any other Mix command in dev/test environments

**Note**: The .env file should not be committed to version control. Add it to your `.gitignore` file.

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