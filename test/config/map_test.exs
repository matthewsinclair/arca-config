defmodule Arca.Config.MapTest do
  use ExUnit.Case, async: false
  
  alias Arca.Config.Map, as: ConfigMap
  alias Arca.Config.Server
  
  setup do
    # Store original environment variables
    app_name = Arca.Config.Cfg.parent_app() |> to_string()
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"
    
    original_env = %{
      app_specific_path: System.get_env(app_specific_path_var),
      app_specific_file: System.get_env(app_specific_file_var),
      config_path: System.get_env("ARCA_CONFIG_PATH"),
      config_file: System.get_env("ARCA_CONFIG_FILE")
    }
    
    # Set up test config file
    test_dir = Path.join(System.tmp_dir(), "arca_map_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)
    test_file = Path.join(test_dir, "test_config.json")
    
    # Set environment variables for test - use app-specific variables since they take precedence
    System.put_env(app_specific_path_var, test_dir)
    System.put_env(app_specific_file_var, "test_config.json")
    
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
    
    # Start the necessary processes with proper error handling
    try do
      # Try to start the registry if it's not already running
      if !Process.whereis(Arca.Config.Registry) do
        start_supervised!({Registry, keys: :duplicate, name: Arca.Config.Registry})
      end
      
      # Try to start the cache if it's not already running
      if !Process.whereis(Arca.Config.Cache) do
        start_supervised!(Arca.Config.Cache)
      end
      
      # Try to start the server if it's not already running
      if !Process.whereis(Arca.Config.Server) do
        start_supervised!(Arca.Config.Server)
      end
    rescue
      _e -> :ok  # Ignore errors from processes already started
    end
    
    # Reload the server with new config
    Server.reload()
    
    on_exit(fn ->
      # Restore original environment variables
      if original_env.app_specific_path, do: System.put_env(app_specific_path_var, original_env.app_specific_path), else: System.delete_env(app_specific_path_var)
      if original_env.app_specific_file, do: System.put_env(app_specific_file_var, original_env.app_specific_file), else: System.delete_env(app_specific_file_var)
      if original_env.config_path, do: System.put_env("ARCA_CONFIG_PATH", original_env.config_path), else: System.delete_env("ARCA_CONFIG_PATH")
      if original_env.config_file, do: System.put_env("ARCA_CONFIG_FILE", original_env.config_file), else: System.delete_env("ARCA_CONFIG_FILE")
      
      # Clean up test directory
      File.rm_rf!(test_dir)
    end)
    
    {:ok, %{config: ConfigMap.new()}}
  end
  
  describe "get/3" do
    test "retrieves a value by key", %{config: config} do
      assert "TestApp" = ConfigMap.get(config, "app.name")
    end
    
    test "returns default for non-existent key", %{config: config} do
      assert "default" = ConfigMap.get(config, "missing", "default")
    end
    
    test "returns nil for non-existent key with no default", %{config: config} do
      assert is_nil(ConfigMap.get(config, "missing"))
    end
  end
  
  describe "get_in/3" do
    test "retrieves a value by key path", %{config: config} do
      assert "TestApp" = ConfigMap.get_in(config, ["app", "name"])
    end
    
    test "returns default for non-existent path", %{config: config} do
      assert "default" = ConfigMap.get_in(config, ["app", "missing"], "default")
    end
  end
  
  describe "put/3" do
    test "updates a value", %{config: config} do
      # Update a value
      new_config = ConfigMap.put(config, "app.name", "NewApp")
      
      # Check the value was updated
      assert "NewApp" = ConfigMap.get(new_config, "app.name")
      
      # Check it's also accessible through Server API
      assert {:ok, "NewApp"} = Server.get("app.name")
    end
    
    test "returns the same struct", %{config: config} do
      new_config = ConfigMap.put(config, "app.name", "NewApp")
      assert %ConfigMap{} = new_config
    end
    
    test "raises on error" do
      # Force an error by making the config file non-writable
      # This is a bit tricky to test, so we'll mock the Server.put to return an error
      # No need to call Code.ensure_loaded as Server is already aliased
      
      try do
        :meck.new(Server, [:passthrough])
        :meck.expect(Server, :put, fn _, _ -> {:error, "Test error"} end)
        
        assert_raise RuntimeError, fn ->
          ConfigMap.put(ConfigMap.new(), "test", "value") 
        end
      after
        if :meck.validate(Server) do
          :meck.unload(Server)
        end
      end
    end
  end
  
  describe "put_in/3" do
    test "updates a value by path", %{config: config} do
      # Update a nested value
      new_config = ConfigMap.put_in(config, ["database", "host"], "new-host")
      
      # Check the value was updated
      assert "new-host" = ConfigMap.get_in(new_config, ["database", "host"])
      
      # Check it's also accessible through Server API
      assert {:ok, "new-host"} = Server.get(["database", "host"])
    end
  end
  
  describe "has_key?/2" do
    test "returns true for existing key", %{config: config} do
      assert ConfigMap.has_key?(config, "app.name")
    end
    
    test "returns false for non-existent key", %{config: config} do
      refute ConfigMap.has_key?(config, "missing")
    end
  end
  
  describe "Access behavior" do
    test "supports bracket access for getting values", %{config: config} do
      assert "TestApp" = config["app"]["name"]
      assert 5432 = config["database"]["port"]
    end
    
    test "bracket access with non-existent key returns nil", %{config: config} do
      assert is_nil(config["missing"])
    end
    
    test "get_and_update works with Access.get_and_update", %{config: config} do
      {old_value, new_config} = Access.get_and_update(config, "app.name", fn current ->
        {current, "UpdatedName"}
      end)
      
      assert old_value == "TestApp"
      assert "UpdatedName" = ConfigMap.get(new_config, "app.name")
    end
    
    test "pop works with Access.pop", %{config: config} do
      {value, _config} = Access.pop(config, "app.name")
      assert value == "TestApp"
      
      # Since we can't actually remove keys, the original should still be there
      assert {:ok, "TestApp"} = Server.get("app.name")
    end
  end
end