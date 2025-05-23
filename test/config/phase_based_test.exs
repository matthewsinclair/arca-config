defmodule Arca.Config.PhaseBasedTest do
  use ExUnit.Case, async: false

  setup do
    # Clean up application config
    Application.delete_env(:arca_config, :config_domain)

    # Reset FileWatcher to dormant state
    send(Arca.Config.FileWatcher, {:reset_to_dormant, self()})

    on_exit(fn ->
      Application.delete_env(:arca_config, :config_domain)
      # Reset FileWatcher to dormant state after test
      send(Arca.Config.FileWatcher, {:reset_to_dormant, self()})
    end)
  end

  test "load_config_phase/0 loads configuration and starts file watching" do
    # Create test config file
    test_path = System.tmp_dir!()
    test_file = "phase_test.json"
    full_path = Path.join(test_path, test_file)

    # Write test config
    File.write!(full_path, Jason.encode!(%{"test_key" => "test_value"}))

    # Set environment for test
    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)

    # Simulate application setting config domain before phase
    Application.put_env(:arca_config, :config_domain, :test_app)

    try do
      # Load configuration during phase
      assert :ok = Arca.Config.load_config_phase()

      # Configuration should be accessible
      assert {:ok, "test_value"} = Arca.Config.get("test_key")

      # FileWatcher should be active (can verify by checking state)
      file_watcher_state = :sys.get_state(Arca.Config.FileWatcher)
      assert file_watcher_state.watching == true
    after
      # Clean up
      File.rm(full_path)
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
    end
  end

  test "system works with on-demand config loading when no phase called" do
    # Create test config file
    test_path = System.tmp_dir!()
    test_file = "phase_test2.json"
    full_path = Path.join(test_path, test_file)

    # Write test config
    File.write!(full_path, Jason.encode!(%{"test_key" => "test_value"}))

    # Set environment for test
    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)

    # Simulate application setting config domain
    Application.put_env(:arca_config, :config_domain, :test_app)

    try do
      # Clear any loaded config to test on-demand loading
      GenServer.call(Arca.Config.Server, {:reset_for_test, %{}})

      # Config access should trigger on-demand loading
      assert {:ok, "test_value"} = Arca.Config.get("test_key")

      # Verify config was loaded on-demand
      server_state = :sys.get_state(Arca.Config.Server)
      assert server_state.loaded == true
      assert map_size(server_state.config) > 0
    after
      # Clean up
      File.rm(full_path)
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
    end
  end

  test "environment overrides are applied during phase loading" do
    # Create test config file
    test_path = System.tmp_dir!()
    test_file = "phase_test3.json"
    full_path = Path.join(test_path, test_file)

    # Write test config
    File.write!(full_path, Jason.encode!(%{"database" => %{"host" => "localhost"}}))

    # Set environment for test
    System.put_env("TEST_APP_CONFIG_PATH", test_path)
    System.put_env("TEST_APP_CONFIG_FILE", test_file)

    Application.put_env(:arca_config, :config_domain, :test_app)

    try do
      # Set environment override
      System.put_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT", "5432")

      # Load configuration during phase
      assert :ok = Arca.Config.load_config_phase()

      # Override should be applied
      assert {:ok, 5432} = Arca.Config.get("database.port")
      assert {:ok, "localhost"} = Arca.Config.get("database.host")
    after
      # Clean up
      File.rm(full_path)
      System.delete_env("TEST_APP_CONFIG_PATH")
      System.delete_env("TEST_APP_CONFIG_FILE")
      System.delete_env("TEST_APP_CONFIG_OVERRIDE_DATABASE_PORT")
    end
  end
end
