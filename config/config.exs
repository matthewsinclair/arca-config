# General application configuration
import Config

# Load environment variables from .env file in dev and test environments
import_config "dotenv.exs"

# Configure Arca.Config
config :arca_config,
  env: config_env(),
  name: "arca_config",
  about: "🛠️ Arca Config",
  description: "A simple file-based configurator for Elixir apps",
  version: "0.1.0",
  author: "hello@arca.io",
  url: "https://arca.io",
  config_domain: :arca_config

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
