import Config

# Configure logger for test environment
# Set to :warning to suppress info/debug messages during tests
config :logger, level: :warning

# Optionally, you can completely disable logger output in tests:
# config :logger, backends: []