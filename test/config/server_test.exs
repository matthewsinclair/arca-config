defmodule Arca.Config.ServerTest do
  use ExUnit.Case, async: false
  
  alias Arca.Config.Server
  
  setup do
    # Store original environment variables
    original_env = %{
      config_path: System.get_env("ARCA_CONFIG_PATH"),
      config_file: System.get_env("ARCA_CONFIG_FILE")
    }
    
    # Set up test config file
    test_dir = Path.join(System.tmp_dir(), "arca_config_test_#{:rand.uniform(1000)}")
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
        },
        "database" => %{
          "host" => "localhost",
          "port" => 5432
        }
      }, pretty: true)
    )
    
    # Start necessary processes for testing
    # Use nested try to avoid issues with already started processes
    registry_started = try do
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
      if original_env.config_path, do: System.put_env("ARCA_CONFIG_PATH", original_env.config_path), else: System.delete_env("ARCA_CONFIG_PATH")
      if original_env.config_file, do: System.put_env("ARCA_CONFIG_FILE", original_env.config_file), else: System.delete_env("ARCA_CONFIG_FILE")
      
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
        (Arca.Config.Server, :get_config) -> 
          {:ok, %{"test" => "tuple_response"}} 
        (mod, msg) -> 
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
      Process.sleep(100) # Give a moment for processes to start
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
  end
end