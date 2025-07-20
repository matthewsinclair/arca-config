# Arca.Config Upgrade Prompt for Claude Code

This prompt guides upgrading an existing project that uses Arca.Config to the latest version with Registry integration, file watching, and callbacks.

## Instructions for Claude

You are helping upgrade a project that uses the Arca.Config library to the latest version which includes several important improvements:

1. Integration with Elixir Registry for more robust configuration management
2. File watching capabilities to detect external changes to config files
3. Callback registration system for reacting to configuration changes
4. Asynchronous file writes to avoid blocking
5. Improved error handling and process resilience

Please implement the following changes to upgrade the project:

### Step 1: Update Dependencies

First, update the dependency in `mix.exs`:

```elixir
def deps do
  [
    # Update the Arca.Config dependency to the latest version
    {:arca_config, "~> 0.5.0"}, # Or the latest version available
    # Other dependencies...
  ]
end
```

### Step 2: Update Application Supervision Tree

If the application has a custom supervision tree, ensure it's compatible with the new Arca.Config:

1. Check if the application manually starts Arca.Config
2. If it does, update to use the new supervisor structure:

```elixir
# Previous structure (if present)
children = [
  {Arca.Config, []}
]

# New structure
children = [
  {Arca.Config.Supervisor, []}
]
```

### Step 3: Update Configuration Usage

Examine and update code that uses Arca.Config:

1. Find all places where configuration is accessed using `Arca.Config`
2. The basic API (`get/1`, `get!/1`, `put/2`, `put!/2`, `reload/0`) remains unchanged
3. Replace any usage of internal/private modules with the public API

### Step 4: Review Existing Notification Handling

1. Find any code that might be watching for configuration changes
2. Replace custom change detection with the new callback registration system:

```elixir
# Register a callback for configuration changes
{:ok, :registered} = Arca.Config.register_change_callback(:my_component, fn config ->
  # Handle config changes
  IO.puts("Configuration changed: #{inspect(config)}")
  # Perform necessary updates based on the new configuration
end)

# Later, when no longer needed
{:ok, :unregistered} = Arca.Config.unregister_change_callback(:my_component)
```

### Step 5: Implement Subscription-Based Components (if needed)

If components need to watch for specific config key changes:

```elixir
# Subscribe to changes for a specific config key
{:ok, :subscribed} = Arca.Config.subscribe("app.feature.setting")

# In a GenServer or other process, handle subscription messages
def handle_info({:config_updated, key_path, new_value}, state) do
  # Handle the configuration update for the specific key
  {:noreply, state}
end

# When no longer needed
{:ok, :unsubscribed} = Arca.Config.unsubscribe("app.feature.setting")
```

### Step 6: Test the Upgrade

1. Run the test suite to ensure everything works with the new version
2. Test the file watching by manually editing the config file while the application is running
3. Verify that registered callbacks are triggered when configuration changes

### Step 7: Update Documentation (if applicable)

Update any project documentation to reflect:

1. The new callback registration feature
2. File watching capabilities
3. Any changes to how configuration is accessed or updated

## Common Issues and Solutions

### Process Crashes After Upgrade

If you encounter crashes related to Arca.Config processes:

1. Check application supervision tree (Step 2)
2. Ensure you're not using any deprecated or internal modules
3. Verify callback functions don't raise exceptions

### Missing Configuration Updates

If configuration changes aren't being detected:

1. Verify the file watcher is running (check with `:sys.get_state(Arca.Config.FileWatcher)`)
2. Check if the configuration file path is correct
3. Ensure callbacks are properly registered

### Performance Issues

The new version uses asynchronous writes and is more efficient, but if you notice performance issues:

1. Limit the number of callbacks registered
2. Ensure callback functions are lightweight and don't block
3. Consider batching configuration changes when possible

## Additional Notes

- All configuration data is now automatically cached in ETS for faster access
- File writes are asynchronous and will not block the server
- Changes made to the configuration file outside the application will be detected and loaded
- Callbacks provide a clean way to react to configuration changes without polling
