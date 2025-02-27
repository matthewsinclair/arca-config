defmodule Arca.Config.AutoConfigTest do
  use ExUnit.Case
  alias Arca.Config.Cfg

  setup do
    # Store original env vars to restore after test
    original_vars = %{
      arca_path: System.get_env("ARCA_CONFIG_PATH"),
      arca_file: System.get_env("ARCA_CONFIG_FILE"),
      custom_path: System.get_env("ARCA_CONFIG_TEST_PATH"),
      custom_file: System.get_env("ARCA_CONFIG_TEST_FILE")
    }

    # Clean up env after test
    on_exit(fn ->
      # Restore original values or unset if they were not set
      if original_vars.arca_path, do: System.put_env("ARCA_CONFIG_PATH", original_vars.arca_path), else: System.delete_env("ARCA_CONFIG_PATH")
      if original_vars.arca_file, do: System.put_env("ARCA_CONFIG_FILE", original_vars.arca_file), else: System.delete_env("ARCA_CONFIG_FILE")
      if original_vars.custom_path, do: System.put_env("ARCA_CONFIG_TEST_PATH", original_vars.custom_path), else: System.delete_env("ARCA_CONFIG_TEST_PATH")
      if original_vars.custom_file, do: System.put_env("ARCA_CONFIG_TEST_FILE", original_vars.custom_file), else: System.delete_env("ARCA_CONFIG_TEST_FILE")
    end)

    # Clean the environment for tests
    System.delete_env("ARCA_CONFIG_PATH")
    System.delete_env("ARCA_CONFIG_FILE")
    System.delete_env("ARCA_CONFIG_TEST_PATH")
    System.delete_env("ARCA_CONFIG_TEST_FILE")

    :ok
  end

  describe "parent_app/0" do
    test "returns the parent app name" do
      # In the test environment, the parent app should be :arca_config
      assert Cfg.parent_app() == :arca_config
    end
  end
  
  describe "config_file/0" do
    test "prefers home config file if it exists" do
      # Set up temp directories
      home_path = Path.join(System.tmp_dir!(), "arca_test_home")
      local_path = Path.join(System.tmp_dir!(), "arca_test_local")
      
      File.mkdir_p!(home_path)
      File.mkdir_p!(local_path)
      
      # Override paths with environment variables
      System.put_env("ARCA_CONFIG_PATH", home_path)
      System.put_env("ARCA_LOCAL_CONFIG_PATH", local_path)
      
      home_config = Path.join(home_path, Cfg.config_filename())
      local_config = Path.join(local_path, Cfg.config_filename())
      
      try do
        # Write test files
        File.write!(home_config, "{\"test\": \"home\"}")
        File.write!(local_config, "{\"test\": \"local\"}")
        
        # Verify home config is preferred
        assert Cfg.config_file() == Path.join(home_path, Cfg.config_filename())
      after
        # Clean up test files and env vars
        File.rm_rf!(home_path)
        File.rm_rf!(local_path)
        System.delete_env("ARCA_CONFIG_PATH")
        System.delete_env("ARCA_LOCAL_CONFIG_PATH")
      end
    end
    
    test "falls back to local config if home config doesn't exist" do
      # Set up temp directories
      home_path = Path.join(System.tmp_dir!(), "arca_test_home_not_exist")
      local_path = Path.join(System.tmp_dir!(), "arca_test_local_fallback") 
      
      File.mkdir_p!(local_path)
      
      # Override paths with environment variables
      System.put_env("ARCA_CONFIG_PATH", home_path)
      System.put_env("ARCA_LOCAL_CONFIG_PATH", local_path)
      
      local_config = Path.join(local_path, Cfg.config_filename())
      
      try do
        # Write test file only in local path
        File.write!(local_config, "{\"test\": \"local\"}")
        
        # Verify local config is used when home config doesn't exist
        assert Cfg.config_file() == Path.join(local_path, Cfg.config_filename())
      after
        # Clean up test files and env vars
        File.rm_rf!(local_path)
        System.delete_env("ARCA_CONFIG_PATH")
        System.delete_env("ARCA_LOCAL_CONFIG_PATH")
      end
    end
  end

  describe "env_var_prefix/0" do
    test "returns the uppercase parent app name" do
      assert Cfg.env_var_prefix() == "ARCA_CONFIG"
    end
  end

  describe "default_config_path/0" do
    test "uses parent app name when no override provided" do
      # Reset any application config
      Application.delete_env(:arca_config, :default_config_path)
      
      # We'll just assert the format of the path since we can't easily 
      # mock the parent app in this environment
      app_name = Cfg.parent_app() |> to_string()
      expected_path = "~/.#{app_name}/"
      
      result = Cfg.default_config_path()
      
      assert result == expected_path
    end

    test "uses app config when provided" do
      # Set application config to override default path
      Application.put_env(:arca_config, :default_config_path, "~/custom/path/")
      
      assert Cfg.default_config_path() == "~/custom/path/"
      
      # Reset application config
      Application.put_env(:arca_config, :default_config_path, nil)
    end
  end

  describe "local_config_pathname/0" do
    test "uses generic env var first" do
      System.put_env("ARCA_LOCAL_CONFIG_PATH", "/generic/local/path/")
      System.put_env("ARCA_CONFIG_LOCAL_CONFIG_PATH", "/specific/local/path/")
      
      assert Cfg.local_config_pathname() == "/generic/local/path/"
    end

    test "uses app-specific env var second" do
      System.delete_env("ARCA_LOCAL_CONFIG_PATH")
      System.put_env("ARCA_CONFIG_LOCAL_CONFIG_PATH", "/specific/local/path/")
      
      assert Cfg.local_config_pathname() == "/specific/local/path/"
    end

    test "uses application config third" do
      System.delete_env("ARCA_LOCAL_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_LOCAL_CONFIG_PATH")
      
      Application.put_env(:arca_config, :local_config_path, "/app/local/config/path/")
      
      assert Cfg.local_config_pathname() == "/app/local/config/path/"
      
      # Reset application config
      Application.put_env(:arca_config, :local_config_path, nil)
    end

    test "uses default local path as last resort" do
      System.delete_env("ARCA_LOCAL_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_LOCAL_CONFIG_PATH")
      Application.delete_env(:arca_config, :local_config_path)
      
      # Get the actual default path and verify it's used
      default_path = Cfg.local_config_path()
      result = Cfg.local_config_pathname()
      
      assert result == default_path
    end
  end

  describe "config_pathname/0" do
    test "uses generic env var first" do
      System.put_env("ARCA_CONFIG_PATH", "/generic/path/")
      System.put_env("ARCA_CONFIG_TEST_PATH", "/specific/path/")
      
      assert Cfg.config_pathname() == "/generic/path/"
    end

    test "uses app-specific env var second" do
      System.delete_env("ARCA_CONFIG_PATH")
      System.put_env("ARCA_CONFIG_CONFIG_PATH", "/specific/path/")
      
      assert Cfg.config_pathname() == "/specific/path/"
    end

    test "uses application config third" do
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_CONFIG_PATH")
      
      Application.put_env(:arca_config, :config_path, "/app/config/path/")
      
      assert Cfg.config_pathname() == "/app/config/path/"
      
      # Reset application config
      Application.put_env(:arca_config, :config_path, nil)
    end

    test "uses default path as last resort" do
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_CONFIG_PATH")
      Application.delete_env(:arca_config, :config_path)
      
      # Get the actual default path and verify it's used
      default_path = Cfg.default_config_path()
      result = Cfg.config_pathname()
      
      assert result == default_path
    end
  end

  describe "config_filename/0" do
    test "uses generic env var first" do
      System.put_env("ARCA_CONFIG_FILE", "generic.json")
      System.put_env("ARCA_CONFIG_CONFIG_FILE", "specific.json")
      
      assert Cfg.config_filename() == "generic.json"
    end

    test "uses app-specific env var second" do
      System.delete_env("ARCA_CONFIG_FILE")
      System.put_env("ARCA_CONFIG_CONFIG_FILE", "specific.json")
      
      assert Cfg.config_filename() == "specific.json"
    end

    test "uses application config third" do
      System.delete_env("ARCA_CONFIG_FILE")
      System.delete_env("ARCA_CONFIG_CONFIG_FILE")
      
      Application.put_env(:arca_config, :config_file, "app_config.json")
      
      assert Cfg.config_filename() == "app_config.json"
      
      # Reset application config
      Application.put_env(:arca_config, :config_file, nil)
    end

    test "uses default filename as last resort" do
      System.delete_env("ARCA_CONFIG_FILE")
      System.delete_env("ARCA_CONFIG_CONFIG_FILE")
      Application.put_env(:arca_config, :config_file, nil)
      
      assert Cfg.config_filename() == "config.json"
    end
  end
end