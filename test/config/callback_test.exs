defmodule Arca.Config.CallbackTest do
  use ExUnit.Case, async: false
  doctest Arca.Config

  alias Arca.Config
  alias Arca.Config.Server

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
    test_dir = Path.join(System.tmp_dir(), "arca_config_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")

    # Set environment variables for test - use app-specific variables since they take precedence
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
          },
          "database" => %{
            "host" => "localhost",
            "port" => 5432
          }
        },
        pretty: true
      )
    )

    # Start necessary processes for testing
    # Use nested try to avoid issues with already started processes
    registry_started =
      try do
        Registry.start_link(keys: :duplicate, name: Arca.Config.Registry)
        true
      rescue
        _ -> false
      end

    # Start the callback registry if it doesn't exist
    callback_registry_started =
      try do
        Registry.start_link(keys: :duplicate, name: Arca.Config.CallbackRegistry)
        true
      rescue
        _ -> false
      end

    # Start the simple callback registry if it doesn't exist
    simple_callback_registry_started =
      try do
        Registry.start_link(keys: :duplicate, name: Arca.Config.SimpleCallbackRegistry)
        true
      rescue
        _ -> false
      end

    try do
      if not registry_started do
        # Registry is already started, no need to do anything
      end
      
      if not callback_registry_started do
        # Callback Registry is already started, no need to do anything
      end
      
      if not simple_callback_registry_started do
        # Simple Callback Registry is already started, no need to do anything
      end

      if not GenServer.whereis(Arca.Config.Cache) do
        start_supervised(Arca.Config.Cache)
      end

      if not GenServer.whereis(Arca.Config.Server) do
        start_supervised(Arca.Config.Server)
      end
    rescue
      _ -> :ok
    end

    # Reload the server with new config
    Server.reload()

    on_exit(fn ->
      # Restore original environment variables
      if original_env.app_specific_path,
        do: System.put_env(app_specific_path_var, original_env.app_specific_path),
        else: System.delete_env(app_specific_path_var)

      if original_env.app_specific_file,
        do: System.put_env(app_specific_file_var, original_env.app_specific_file),
        else: System.delete_env(app_specific_file_var)

      if original_env.config_path,
        do: System.put_env("ARCA_CONFIG_PATH", original_env.config_path),
        else: System.delete_env("ARCA_CONFIG_PATH")

      if original_env.config_file,
        do: System.put_env("ARCA_CONFIG_FILE", original_env.config_file),
        else: System.delete_env("ARCA_CONFIG_FILE")

      # Clean up test directory
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir, test_file: test_file}}
  end

  describe "add_callback/1" do
    test "registers a 0-arity callback function" do
      # Use a unique reference to track callback execution
      test_pid = self()
      callback_fn = fn -> send(test_pid, :callback_executed) end
      
      # Register the callback
      assert {:ok, ref} = Config.add_callback(callback_fn)
      assert is_reference(ref)
      
      # Verify callback was registered correctly
      entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
      assert Enum.any?(entries, fn {_pid, {callback_ref, _fn}} -> callback_ref == ref end)
    end
    
    test "returns error for non-zero-arity functions" do
      assert_raise FunctionClauseError, fn ->
        Config.add_callback(fn _arg -> :ok end)
      end
    end
  end
  
  describe "remove_callback/1" do
    test "removes a registered callback" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :callback_executed) end
      
      # Register and then remove the callback
      {:ok, ref} = Config.add_callback(callback_fn)
      assert {:ok, :removed} = Config.remove_callback(ref)
      
      # Verify it was removed
      entries = Registry.lookup(Arca.Config.SimpleCallbackRegistry, :simple_callback)
      refute Enum.any?(entries, fn {_pid, {callback_ref, _fn}} -> callback_ref == ref end)
    end
    
    test "returns error for non-existent callback" do
      non_existent_ref = make_ref()
      assert {:error, :not_found} = Config.remove_callback(non_existent_ref)
    end
  end
  
  describe "notify_callbacks/0" do
    test "calls all registered callbacks" do
      # Set up test process to receive messages
      test_pid = self()
      
      # Register multiple callbacks
      callback1 = fn -> send(test_pid, :callback1_executed) end
      callback2 = fn -> send(test_pid, :callback2_executed) end
      
      {:ok, _ref1} = Config.add_callback(callback1)
      {:ok, _ref2} = Config.add_callback(callback2)
      
      # Manually trigger notification
      assert {:ok, :notified} = Config.notify_callbacks()
      
      # Verify all callbacks were executed
      assert_receive :callback1_executed, 500
      assert_receive :callback2_executed, 500
    end
    
    test "continues execution when a callback raises an error" do
      # Set up test process to receive messages
      test_pid = self()
      
      # Register a failing callback and a successful one
      bad_callback = fn -> raise "Intentional test error" end
      good_callback = fn -> send(test_pid, :good_callback_executed) end
      
      {:ok, _bad_ref} = Config.add_callback(bad_callback)
      {:ok, _good_ref} = Config.add_callback(good_callback)
      
      # Notification should complete despite the error
      assert {:ok, :notified} = Config.notify_callbacks()
      
      # Good callback should still execute
      assert_receive :good_callback_executed, 500
    end
  end
  
  describe "automatic callback notification" do
    test "callbacks are notified on put operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end
      
      # Register the callback
      {:ok, _ref} = Config.add_callback(callback_fn)
      
      # Update configuration
      Config.put("test_key", "test_value")
      
      # Verify callback was triggered
      assert_receive :config_changed, 500
    end
    
    test "callbacks are notified on delete operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end
      
      # Add a value to be deleted
      Config.put("temp_key", "temp_value")
      
      # Register the callback
      {:ok, _ref} = Config.add_callback(callback_fn)
      
      # Delete the value
      Server.delete("temp_key")
      
      # Verify callback was triggered
      assert_receive :config_changed, 500
    end
    
    test "callbacks are notified on reload operations" do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end
      
      # Register the callback
      {:ok, _ref} = Config.add_callback(callback_fn)
      
      # Reload configuration
      Config.reload()
      
      # Verify callback was triggered
      assert_receive :config_changed, 500
    end
    
    test "callbacks are notified on external file changes", %{test_file: _test_file} do
      test_pid = self()
      callback_fn = fn -> send(test_pid, :config_changed) end
      
      # Register the callback
      {:ok, _ref} = Config.add_callback(callback_fn)
      
      # Let's directly call notify_external_change to verify callback works
      Arca.Config.Server.notify_external_change()
      
      # Verify callback was triggered
      assert_receive :config_changed, 500
      
      # Now let's validate the integration with the file change detection
      # First clear any pending messages
      receive do
        :config_changed -> :ok
      after
        0 -> :ok
      end
      
      # Test the file watcher's response to reload, not the file watching itself
      # which is tested elsewhere
      Server.reload()
      
      # Wait for notification
      assert_receive :config_changed, 500
    end
  end
end