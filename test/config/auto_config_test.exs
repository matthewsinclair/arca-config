defmodule Arca.Config.AutoConfigTest do
  use ExUnit.Case, async: false

  setup do
    # Generate a unique test directory
    test_dir = Path.join(System.tmp_dir(), "arca_auto_config_test_#{:rand.uniform(1000)}")
    File.mkdir_p!(test_dir)

    # Set up the environment
    env_prefix = "TEST_APP"
    System.put_env("#{env_prefix}_CONFIG_PATH", test_dir)
    System.put_env("#{env_prefix}_CONFIG_FILE", "test_config.json")

    # Set up an override value
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_DATABASE_HOST", "localhost")
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_SERVER_PORT", "5432")
    System.put_env("#{env_prefix}_CONFIG_OVERRIDE_DEBUG_ENABLED", "true")

    # Set the config domain
    Application.put_env(:arca_config, :config_domain, :test_app)

    on_exit(fn ->
      # Clean up environment variables
      System.delete_env("#{env_prefix}_CONFIG_PATH")
      System.delete_env("#{env_prefix}_CONFIG_FILE")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_DATABASE_HOST")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_SERVER_PORT")
      System.delete_env("#{env_prefix}_CONFIG_OVERRIDE_DEBUG_ENABLED")

      # Cleanup the test directory
      File.rm_rf!(test_dir)
    end)

    {:ok, %{test_dir: test_dir, config_file: Path.join(test_dir, "test_config.json")}}
  end

  test "apply_env_overrides applies environment variables to config file", %{
    config_file: config_file
  } do
    # Create an initial config file
    initial_config = %{
      "database" => %{
        "host" => "initial-host"
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Apply the overrides
    Arca.Config.apply_env_overrides()

    # Read the config file directly to verify the changes
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify the overrides were applied
    assert config["database"]["host"] == "localhost"
    # Converted to integer
    assert config["server"]["port"] == 5432
    # Converted to boolean
    assert config["debug"]["enabled"] == true
  end

  test "environment overrides don't erase existing config values", %{config_file: config_file} do
    # Create an initial config file with some nested values
    initial_config = %{
      "database" => %{
        "host" => "initial-host",
        "username" => "dbuser",
        "password" => "secret"
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Apply the overrides
    Arca.Config.apply_env_overrides()

    # Read the config file directly to verify the changes
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify only the override was applied, other values remain
    assert config["database"]["host"] == "localhost"
    assert config["database"]["username"] == "dbuser"
    assert config["database"]["password"] == "secret"
  end

  test "environment overrides are applied through start function", %{config_file: config_file} do
    # Create an initial config file with some values
    initial_config = %{
      "database" => %{
        "host" => "initial-host",
        "port" => 1234
      }
    }

    File.write!(config_file, Jason.encode!(initial_config, pretty: true))

    # Call start directly, which should apply env overrides
    Arca.Config.start(:normal, [])

    # Wait for initialization to complete (initializer uses 500ms delay)
    :timer.sleep(700)

    # Force a reload to make sure we get the latest values
    Arca.Config.reload()

    # Verify the config was updated in the file
    config_content = File.read!(config_file)
    config = Jason.decode!(config_content)

    # Verify values were properly overridden
    assert config["database"]["host"] == "localhost"
    assert config["server"]["port"] == 5432
    assert config["debug"]["enabled"] == true

    # Verify we can retrieve the values through the API
    assert {:ok, "localhost"} = Arca.Config.get("database.host")
    assert {:ok, 5432} = Arca.Config.get("server.port")
    assert {:ok, true} = Arca.Config.get("debug.enabled")
  end
end
