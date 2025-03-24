defmodule Arca.Config.ServerTest do
  use ExUnit.Case, async: false

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

    try do
      if not registry_started do
        # Registry is already started, no need to do anything
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

  describe "get/1" do
    test "retrieves a value by string key" do
      assert {:ok, "TestApp"} = Server.get("app.name")
    end

    test "retrieves a value by atom key" do
      assert {:ok, "TestApp"} = Server.get(:"app.name")
    end

    test "retrieves a value by list key" do
      assert {:ok, "TestApp"} = Server.get(["app", "name"])
    end

    test "returns error for non-existent key" do
      assert {:error, _} = Server.get("non.existent")
    end

    test "retrieves nested maps" do
      assert {:ok, %{"host" => "localhost", "port" => 5432}} = Server.get("database")
    end
  end

  describe "get!/1" do
    test "retrieves a value by key" do
      assert "TestApp" = Server.get!("app.name")
    end

    test "raises for non-existent key" do
      assert_raise RuntimeError, fn -> Server.get!("non.existent") end
    end
  end

  describe "put/2" do
    test "updates an existing value" do
      assert {:ok, "NewApp"} = Server.put("app.name", "NewApp")
      assert {:ok, "NewApp"} = Server.get("app.name")
    end

    test "creates a new nested value" do
      assert {:ok, "production"} = Server.put("app.environment", "production")
      assert {:ok, "production"} = Server.get("app.environment")
    end

    test "creates a deeply nested value" do
      assert {:ok, "admin"} = Server.put(["database", "user", "name"], "admin")
      assert {:ok, "admin"} = Server.get(["database", "user", "name"])
      assert {:ok, %{"name" => "admin"}} = Server.get(["database", "user"])
    end

    test "correctly handles absolute paths when writing config", %{test_dir: test_dir} do
      # Set environment variable to use an absolute path
      app_name = Arca.Config.Cfg.config_domain() |> to_string()
      app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
      app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

      # Create a special absolute path for this test
      absolute_path = Path.join(test_dir, "absolute_path_test")
      File.mkdir_p!(absolute_path)

      # Set both path and filename to ensure we know the exact location
      System.put_env(app_specific_path_var, absolute_path)
      System.put_env(app_specific_file_var, "absolute_test.json")

      # Force a reload to pick up new config location
      Server.reload()

      # Determine where config should be written
      config_file = Path.join(absolute_path, "absolute_test.json")

      # Write a config value
      assert {:ok, "test_value"} = Server.put("absolute_path_test", "test_value")

      # Check if the config file was created in the right place
      assert File.exists?(config_file),
             "Config file not found at expected location: #{config_file}"

      # Check the content of the file
      {:ok, content} = File.read(config_file)
      {:ok, decoded} = Jason.decode(content)
      assert decoded["absolute_path_test"] == "test_value"

      # Ensure we can read the value back
      assert {:ok, "test_value"} = Server.get("absolute_path_test")
    end
    
    test "prevents recursive directory creation with absolute paths", %{test_dir: test_dir} do
      # Create a test directory structure that will be the target of our absolute path
      target_dir = Path.join(test_dir, "recursive_test")
      File.mkdir_p!(target_dir)
      
      # Set environment variable to use an absolute path
      app_name = Arca.Config.Cfg.config_domain() |> to_string()
      app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
      app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"
      
      # Save original environment variables
      original_path_env = System.get_env(app_specific_path_var)
      original_file_env = System.get_env(app_specific_file_var)
      
      # First set up with relative path (as would happen in problematic setups)
      local_config_dir = ".temp_config_relative"
      System.put_env(app_specific_path_var, local_config_dir)
      System.put_env(app_specific_file_var, "recursive_test.json")
      
      # Force a reload to pick up initial relative config location
      Server.reload()
      
      # Write a value to the relative path
      assert {:ok, "initial_value"} = Server.put("initial_key", "initial_value")
      
      # Verify a local config was created
      local_config_file = Path.join(local_config_dir, "recursive_test.json")
      assert File.exists?(local_config_file)
      
      # Now switch to absolute path mid-operation (this would have triggered the bug before)
      System.put_env(app_specific_path_var, target_dir)
      
      # Write a second config value - this should use the absolute path
      assert {:ok, "recursive_test_value"} = Server.put("recursive_test_key", "recursive_test_value")
      
      # The expected location of the config file
      config_file = Path.join(target_dir, "recursive_test.json")
      assert File.exists?(config_file), "Config file not found at expected location: #{config_file}"
      
      # Check if a recursive directory structure was created (which would be a bug)
      # Test for the problematic path that was previously created: ./path/absolute/path/...
      recursive_path = Path.join([local_config_dir, target_dir])
      refute File.exists?(recursive_path), "Recursive directory structure was created at: #{recursive_path}"
      
      # Check for the most problematic recursive pattern:
      # Current dir + path component of absolute path
      path_components = Path.split(target_dir)
      deep_recursive_path = Path.join([local_config_dir] ++ path_components)
      refute File.exists?(deep_recursive_path), "Deep recursive directory structure was created at: #{deep_recursive_path}"
      
      # Clean up local config directory
      File.rm_rf!(local_config_dir)
      
      # Restore original environment variables
      if original_path_env, do: System.put_env(app_specific_path_var, original_path_env), else: System.delete_env(app_specific_path_var)
      if original_file_env, do: System.put_env(app_specific_file_var, original_file_env), else: System.delete_env(app_specific_file_var)
    end
  end

  describe "put!/2" do
    test "updates a value and returns it" do
      assert "NewVersion" = Server.put!("app.version", "NewVersion")
      assert {:ok, "NewVersion"} = Server.get("app.version")
    end
  end

  describe "reload/0" do
    test "reloads configuration from disk", %{test_file: test_file} do
      # Modify the file directly
      config = %{
        "app" => %{
          "name" => "UpdatedApp",
          "version" => "2.0.0"
        }
      }

      File.write!(test_file, Jason.encode!(config, pretty: true))

      # Reload should pick up the changes
      assert {:ok, reloaded_config} = Server.reload()
      assert reloaded_config["app"]["name"] == "UpdatedApp"
      assert {:ok, "UpdatedApp"} = Server.get("app.name")
    end
  end

  describe "notify_external_change/0" do
    test "handles both tuple and map responses from get_config" do
      # Register a callback to detect external changes
      test_pid = self()

      Arca.Config.register_change_callback(:test_callback, fn config ->
        send(test_pid, {:callback_received, config})
      end)

      # Test with original get_config implementation (returns map directly)
      Server.notify_external_change()
      assert_receive {:callback_received, config}, 500
      assert is_map(config)

      # Mock the get_config implementation to return {:ok, config} tuple
      :meck.new(GenServer, [:passthrough])

      :meck.expect(GenServer, :call, fn
        Arca.Config.Server, :get_config ->
          {:ok, %{"test" => "tuple_response"}}

        mod, msg ->
          :meck.passthrough([mod, msg])
      end)

      # Test with mocked get_config (returns {:ok, config} tuple)
      Server.notify_external_change()
      assert_receive {:callback_received, tuple_config}, 500
      assert tuple_config["test"] == "tuple_response"

      # Clean up
      Arca.Config.unregister_change_callback(:test_callback)
      :meck.unload(GenServer)
    end
  end

  describe "subscribe/1 and notifications" do
    setup do
      # Make sure registry is clean for these tests
      # Give a moment for processes to start
      Process.sleep(100)
      :ok
    end

    test "notifies subscribers when value changes" do
      # Subscribe to the key
      Server.subscribe("app.name")

      # Update the value
      Server.put("app.name", "NotifiedApp")

      # Check for notification
      assert_receive {:config_updated, ["app", "name"], "NotifiedApp"}, 500
    end

    test "unsubscribe stops notifications" do
      # Subscribe and then unsubscribe
      Server.subscribe("app.version")
      Server.unsubscribe("app.version")

      # Update the value
      Server.put("app.version", "3.0.0")

      # Should not receive notification
      refute_receive {:config_updated, ["app", "version"], "3.0.0"}, 500
    end

    test "parent keys are notified when child changes" do
      # Subscribe to parent
      Server.subscribe("database")

      # Update a child
      Server.put("database.host", "new-host")

      # Should receive notification for database (with updated host)
      assert_receive {:config_updated, ["database"], %{"host" => "new-host", "port" => 5432}}, 500
    end

    test "preserves existing config when updating a top-level key" do
      # Set up initial state with the existing test data
      # We know from the setup that we have app and database keys

      # Update with a new top-level key
      Server.put("llm_client_type", "echo")

      # Verify all original keys are preserved
      assert {:ok, _app_data} = Server.get("app")
      assert {:ok, _db_data} = Server.get("database")
      assert {:ok, "echo"} = Server.get("llm_client_type")

      # The app and database sections should still have their contents
      assert {:ok, "TestApp"} = Server.get("app.name")
      assert {:ok, "localhost"} = Server.get("database.host")
    end
  end
end
