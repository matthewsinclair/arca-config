defmodule Arca.Config.Cfg.Test do
  use ExUnit.Case, async: false
  alias Arca.Config.Cfg

  # Set up temporary test environment for doctests
  setup_all do
    # Set up test paths for doctest
    app_name = Arca.Config.Cfg.config_domain() |> to_string()
    test_path = System.tmp_dir!()
    app_specific_path = ".#{app_name}"
    test_file = "config_test.json"
    app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
    app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"
    
    System.put_env(app_specific_path_var, test_path)
    System.put_env(app_specific_file_var, test_file)

    # Ensure test file exists
    config_file = Path.join(test_path, test_file)
    File.mkdir_p!(Path.dirname(config_file))

    # Create app-specific config directory for file watcher tests
    app_config_dir = Path.join(File.cwd!(), app_specific_path)
    app_config_file = Path.join(app_config_dir, "config.json")
    File.mkdir_p!(app_config_dir)
    
    File.write!(
      config_file,
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )
    
    # Write to app_specific directory too to handle tests that rely on the default path
    File.write!(
      app_config_file,
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )

    on_exit(fn ->
      # Clean up test files
      File.rm(config_file)
      File.rm(app_config_file)
      System.delete_env(app_specific_path_var)
      System.delete_env(app_specific_file_var)
    end)

    :ok
  end

  doctest Arca.Config
  doctest Arca.Config.Cfg

  describe "Arca.Config.Cfg" do
    setup do
      # Get previous env var for config path and file names
      previous_env = System.get_env()
      
      app_name = Arca.Config.Cfg.config_domain() |> to_string()
      app_specific_path = ".#{app_name}"
      app_specific_path_var = "#{String.upcase(app_name)}_CONFIG_PATH"
      app_specific_file_var = "#{String.upcase(app_name)}_CONFIG_FILE"

      # Set up to load the app-specific config file
      System.put_env(app_specific_path_var, app_specific_path)
      System.put_env(app_specific_file_var, "config.json")

      # Write a known config file to a known location
      config_dir = Path.join(File.cwd!(), app_specific_path)
      config_file = Path.join(config_dir, "config.json")
      File.mkdir_p!(config_dir)
      
      File.write!(
        config_file,
        ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
      )

      # Put things back how we found them
      on_exit(fn -> 
        System.put_env(previous_env)
        File.rm(config_file)
      end)
    end

    test "config file path and name" do
      config_pathname = Cfg.config_pathname()
      config_filename = Cfg.config_filename()
      config_file = Cfg.config_file()

      assert config_pathname != nil
      assert config_filename != nil
      assert config_file != nil
      assert config_file === Path.join(config_pathname, config_filename)
    end

    test "config file path and name via env var" do
      # Jam app-specific values into the env vars
      app_specific_path_var = "#{Cfg.env_var_prefix()}_CONFIG_PATH"
      app_specific_file_var = "#{Cfg.env_var_prefix()}_CONFIG_FILE"
      System.put_env(app_specific_path_var, "/tmp/")
      System.put_env(app_specific_file_var, "bozo.json")

      # Test that they are equal to what Cfg thinks they should be
      assert System.get_env(app_specific_path_var) == Cfg.config_pathname()
      assert System.get_env(app_specific_file_var) == Cfg.config_filename()
    end

    test "load valid configuration file (and succeed)" do
      # Check that we can load the default configuration file
      case Cfg.load() do
        {:ok, config} ->
          # will exec
          assert config != nil
          assert config["id"] == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"

        {:error, reason} ->
          # won't exec
          dbg(reason)
          assert reason
      end
    end

    test "load invalid configuration file (and fail)" do
      # Check that if we set up a bad file that load() will fail
      # Jam some rubbish into the env vars
      app_specific_path_var = "#{Cfg.env_var_prefix()}_CONFIG_PATH"
      app_specific_file_var = "#{Cfg.env_var_prefix()}_CONFIG_FILE" 
      System.put_env(app_specific_path_var, "/nonexistent/path/")
      System.put_env(app_specific_file_var, "nonexistent.json")

      # Check that we can load the default configuration file
      case Cfg.load() do
        {:ok, config} ->
          # won't exec - this file shouldn't exist
          dbg(config)
          assert false

        {:error, reason} ->
          # will exec
          assert reason
      end
      
      # Clean up
      System.delete_env(app_specific_path_var)
      System.delete_env(app_specific_file_var)
    end

    test "inspect config property" do
      {:ok, id_from_string} = Cfg.inspect_property("id")
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    test "get config property" do
      {:ok, id_from_string} = Cfg.get("id")
      {:ok, id_from_atom} = Cfg.get(:id)
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
      assert id_from_atom == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    test "get! config property" do
      id_from_string = Cfg.get!("id")
      id_from_atom = Cfg.get!(:id)
      assert id_from_string == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
      assert id_from_atom == "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
    end

    test "put config property" do
      # Use a simple config file with just a timestamp attribute
      temp_dir = System.tmp_dir!()
      System.put_env("ARCA_CONFIG_PATH", temp_dir)
      System.put_env("ARCA_CONFIG_FILE", "timestamp.json")

      # Make sure file exists (and empty)
      config_file = Path.join(temp_dir, "timestamp.json")
      File.write!(config_file, "{}")

      timestamp_in = DateTime.to_string(DateTime.utc_now())

      # Put a new value into the config and ensure that works
      case Cfg.put(:timestamp, timestamp_in) do
        {:ok, value} -> assert value == timestamp_in
        {:error, reason} -> flunk("Error: #{reason}")
      end

      # Grab that value back from the config and ensure that works
      case Cfg.get(:timestamp) do
        {:ok, timestamp_out} -> assert timestamp_out == timestamp_in
        {:error, reason} -> flunk("Error: #{reason}")
      end

      # Remove the file now we're done with it
      File.rm!(config_file)
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_FILE")
    end

    test "put! config property" do
      # Use a simple config file with just a timestamp attribute
      temp_dir = System.tmp_dir!()
      System.put_env("ARCA_CONFIG_PATH", temp_dir)
      System.put_env("ARCA_CONFIG_FILE", "timestamp.json")

      # Make sure file exists (and empty)
      config_file = Path.join(temp_dir, "timestamp.json")
      File.write!(config_file, "{}")

      timestamp_in = DateTime.to_string(DateTime.utc_now())

      # Put a new value into the config and ensure that works
      value = Cfg.put!(:timestamp, timestamp_in)
      assert value == timestamp_in

      # Grab that value back from the config and ensure that works
      timestamp_out = Cfg.get!(:timestamp)
      assert timestamp_out == timestamp_in

      # Remove the file now we're done with it
      File.rm!(config_file)
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_FILE")
    end

    test "config_data_pathname" do
      data_path = Cfg.config_data_pathname()
      expected_path = Path.join([Cfg.config_pathname(), "data", "links"])
      assert data_path == expected_path
    end
  end
end
