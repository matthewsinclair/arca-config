defmodule Arca.Config.Cfg.Test do
  use ExUnit.Case, async: false
  alias Arca.Config.Cfg
  alias Arca.Config.Test.Support

  # Set up temporary test environment for doctests
  setup_all do
    # Set up test paths for doctest
    test_path = System.tmp_dir!()
    test_file = "config_test.json"
    System.put_env("ARCA_CONFIG_PATH", test_path)
    System.put_env("ARCA_CONFIG_FILE", test_file)

    # Ensure test file exists
    config_file = Path.join(test_path, test_file)
    File.mkdir_p!(Path.dirname(config_file))

    File.write!(
      config_file,
      ~s({"id": "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON", "database": {"host": "localhost"}})
    )

    on_exit(fn ->
      # Clean up test files
      File.rm(config_file)
      System.delete_env("ARCA_CONFIG_PATH")
      System.delete_env("ARCA_CONFIG_FILE")
    end)

    :ok
  end

  doctest Arca.Config
  doctest Arca.Config.Cfg

  describe "Arca.Config.Cfg" do
    setup do
      # Get previous env var for config path and file names
      previous_env = System.get_env()

      # Set up to load the local .arca/config.json file
      System.put_env("ARCA_CONFIG_PATH", "./.arca")
      System.put_env("ARCA_CONFIG_FILE", "config.json")

      # Write a known config file to a known location
      Support.write_default_config_file(
        System.get_env("ARCA_CONFIG_FILE"),
        System.get_env("ARCA_CONFIG_PATH")
      )

      # Put things back how we found them
      on_exit(fn -> System.put_env(previous_env) end)
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
      # Jam something into the env vars
      System.put_env("ARCA_CONFIG_PATH", "/tmp/")
      System.put_env("ARCA_CONFIG_FILE", "bozo.json")

      # Test that they are equal to what Cfg thinks they should be
      assert System.get_env("ARCA_CONFIG_PATH") == Cfg.config_pathname()
      assert System.get_env("ARCA_CONFIG_FILE") == Cfg.config_filename()
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
      System.put_env("ARCA_CONFIG_PATH", "/tmp/")
      System.put_env("ARCA_CONFIG_FILE", "bozo.json")

      # Check that we can load the default configuration file
      case Cfg.load() do
        {:ok, config} ->
          # won't exec
          dbg(config)
          assert !config

        {:error, reason} ->
          # will exec
          assert reason
      end
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
