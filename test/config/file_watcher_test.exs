defmodule Arca.Config.FileWatcherTest do
  use ExUnit.Case, async: false
  
  alias Arca.Config.FileWatcher
  
  setup do
    # Store original environment variables
    original_env = %{
      config_path: System.get_env("ARCA_CONFIG_PATH"),
      config_file: System.get_env("ARCA_CONFIG_FILE")
    }
    
    # Set up test config file
    test_dir = Path.join(System.tmp_dir(), "arca_file_watcher_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")
    
    # Set environment variables for test
    System.put_env("ARCA_CONFIG_PATH", test_dir)
    System.put_env("ARCA_CONFIG_FILE", "test_config.json")
    
    # Write initial test config
    File.write!(
      test_file,
      Jason.encode!(%{
        "app" => %{
          "name" => "TestApp",
          "version" => "1.0.0"
        }
      }, pretty: true)
    )
    
    # Start necessary processes
    try do
      # Try to start the registry if it's not already running
      if !Process.whereis(Arca.Config.Registry) do
        start_supervised!({Registry, keys: :duplicate, name: Arca.Config.Registry})
      end
      
      # Try to start the callback registry if it's not already running
      if !Process.whereis(Arca.Config.CallbackRegistry) do
        start_supervised!({Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry})
      end
      
      # Try to start the cache if it's not already running
      if !Process.whereis(Arca.Config.Cache) do
        start_supervised!(Arca.Config.Cache)
      end
      
      # Try to start the server if it's not already running
      if !Process.whereis(Arca.Config.Server) do
        start_supervised!(Arca.Config.Server)
      end
      
      # Start file watcher for testing
      if !Process.whereis(FileWatcher) do
        start_supervised!(FileWatcher)
      end
    rescue
      _e -> :ok  # Ignore errors from processes already started
    end
    
    on_exit(fn ->
      # Restore original environment variables
      if original_env.config_path, do: System.put_env("ARCA_CONFIG_PATH", original_env.config_path), else: System.delete_env("ARCA_CONFIG_PATH")
      if original_env.config_file, do: System.put_env("ARCA_CONFIG_FILE", original_env.config_file), else: System.delete_env("ARCA_CONFIG_FILE")
      
      # Clean up test directory
      File.rm_rf!(test_dir)
    end)
    
    # Return the test file path for use in tests
    {:ok, %{test_file: test_file}}
  end
  
  test "register_write prevents notification loops", %{test_file: test_file} do
    # Register a callback to detect external changes
    test_pid = self()
    Arca.Config.register_change_callback(:test_callback, fn _config ->
      send(test_pid, :config_changed_externally)
    end)
    
    # Get the file watcher's initial state (we don't need to use this, just checking it works)
    _state_before = :sys.get_state(FileWatcher)
    
    # Generate a token and register it with the watcher
    token = System.monotonic_time()
    FileWatcher.register_write(token)
    
    # Verify token was registered
    state_after = :sys.get_state(FileWatcher)
    assert state_after.write_token == token
    
    # Make a change to the config file with this token
    # (simulate what would happen in write_config)
    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "UpdatedApp"}}, pretty: true))
    
    # Force a file check (rather than waiting for the timer)
    send(FileWatcher, :check_file)
    
    # We shouldn't receive a notification since it's our own change
    refute_receive :config_changed_externally, 500
    
    # Clean up
    Arca.Config.unregister_change_callback(:test_callback)
  end
  
  test "detects file changes and notifies the server to reload", %{test_file: test_file} do
    # Override the Server's reload and notify_external_change functions for this test only
    test_pid = self()
    :meck.new(Arca.Config.Server, [:passthrough])
    
    # First mock the reload function which is called first
    :meck.expect(Arca.Config.Server, :reload, fn ->
      # Send a message to the test process to verify this was called
      send(test_pid, :reload_called)
      # Return a successful result
      {:ok, %{}}
    end)
    
    # Then mock the notification function which is called second
    :meck.expect(Arca.Config.Server, :notify_external_change, fn ->
      send(test_pid, :external_change_notification_called)
      {:ok, :notified}
    end)
    
    # Wait a moment for the file watcher to get the initial state
    Process.sleep(100)
    
    # Get current watcher state
    original_state = :sys.get_state(FileWatcher)
    
    # Make a significant change to the file's content
    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "ExternalUpdate", "timestamp" => DateTime.utc_now() |> DateTime.to_string()}}, pretty: true))
    
    # Wait for the file system to register the change
    Process.sleep(100)
    
    # Force the file system to register the change (no need to store the result)
    _ = case File.stat(test_file) do
      {:ok, info} -> info
      _ -> nil
    end
    
    # Update the FileWatcher's state directly to simulate a time difference
    # This is needed because file timestamps might not change reliably in tests
    :sys.replace_state(FileWatcher, fn state -> 
      %{state | last_info: %{original_state.last_info | mtime: {{2000, 1, 1}, {0, 0, 0}}}}
    end)
    
    # Now force a file check
    send(FileWatcher, :check_file)
    
    # Verify that both functions were called in the correct order
    assert_receive :reload_called, 500
    assert_receive :external_change_notification_called, 500
    
    # Clean up
    :meck.unload(Arca.Config.Server)
  end
end