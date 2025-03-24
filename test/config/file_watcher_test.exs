defmodule Arca.Config.FileWatcherTest do
  use ExUnit.Case, async: false

  alias Arca.Config.FileWatcher

  # Test the file watcher functionality without timing dependencies

  setup do
    # Store original environment variables
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

    original_env = %{
      app_specific_path: System.get_env(app_specific_path_var),
      app_specific_file: System.get_env(app_specific_file_var),
      config_path: System.get_env("ARCA_CONFIG_PATH"),
      config_file: System.get_env("ARCA_CONFIG_FILE")
    }

    # Set up test config file
    test_dir = Path.join(System.tmp_dir(), "arca_file_watcher_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")

    # Set environment variables for test
    System.put_env(app_specific_path_var, test_dir)
    System.put_env(app_specific_file_var, "test_config.json")

    # Write initial test config
    File.write!(
      test_file,
      Jason.encode!(
        %{
          "app" => %{
            "name" => "TestApp",
            "version" => "1.0.0"
          }
        },
        pretty: true
      )
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
      # Ignore errors from processes already started
      _e -> :ok
    end

    on_exit(fn ->
      # Restore original environment variables
      if original_env.config_path,
        do: System.put_env("ARCA_CONFIG_PATH", original_env.config_path),
        else: System.delete_env("ARCA_CONFIG_PATH")

      if original_env.config_file,
        do: System.put_env("ARCA_CONFIG_FILE", original_env.config_file),
        else: System.delete_env("ARCA_CONFIG_FILE")

      System.delete_env(app_specific_path_var)
      System.delete_env(app_specific_file_var)

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
    # Mock the Server functions
    test_pid = self()
    :meck.new(Arca.Config.Server, [:passthrough])

    :meck.expect(Arca.Config.Server, :reload, fn ->
      send(test_pid, :reload_called)
      {:ok, %{}}
    end)

    :meck.expect(Arca.Config.Server, :notify_external_change, fn ->
      send(test_pid, :external_change_notification_called)
      {:ok, :notified}
    end)

    # Get the file watcher state
    _state = :sys.get_state(FileWatcher)

    # Prepare different file info structs to simulate a change
    # We'll create "before" and "after" states with different mtimes
    old_info = %{mtime: {{2022, 1, 1}, {12, 0, 0}}, size: 100}
    _new_info = %{mtime: {{2023, 1, 1}, {12, 0, 0}}, size: 200}

    # Now manually call the file watcher's handle_info with our simulated change
    # This directly tests the logic without relying on file system events
    {:noreply, _new_state} =
      FileWatcher.handle_info(
        :check_file,
        %{config_file: test_file, last_info: old_info, write_token: nil}
      )

    # The test above simulates what the GenServer would do when it checks
    # It's hard to verify because we're simulating the implementation

    # Let's try a different approach - directly call handle_info with all the right mocks
    # First, modify the actual file
    File.write!(test_file, Jason.encode!(%{"app" => %{"name" => "ExternalUpdate"}}, pretty: true))

    # Get fresh file info that will actually indicate a change compared to old_info
    {:ok, _real_new_info} = File.stat(test_file)

    # Directly invoke the handle_info callback with our controlled inputs
    {:noreply, _} =
      FileWatcher.handle_info(
        :check_file,
        %{config_file: test_file, last_info: old_info, write_token: nil}
      )

    # Verify both functions were called (these should be almost instant since we're
    # not waiting for file system events)
    assert_receive :reload_called, 100
    assert_receive :external_change_notification_called, 100

    # Clean up
    :meck.unload(Arca.Config.Server)
  end
end
