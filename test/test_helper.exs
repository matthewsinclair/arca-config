# Support functions for CLI test cases
defmodule Arca.Config.Test.Support do
  # Example config file
  @example_config_json_as_map %{
    "database" => %{
      "host" => "localhost"
    },
    "id" => "DOT_SLASH_DOT_LL_SLASH_CONFIG_DOT_JSON"
  }

  # Write a known config file to a known location
  def write_default_config_file(config_file, config_path) do
    config_file
    |> Path.expand(config_path)
    |> File.write(Jason.encode!(@example_config_json_as_map, pretty: true))
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

# Always clean up ALL .test_app directories both before and after all tests
cleanup_dirs = [
  # Home directory
  Path.join(System.user_home!(), ".test_app"),
  # Current working directory
  Path.join(File.cwd!(), ".test_app"),
  # Parent directory
  Path.join(Path.dirname(File.cwd!()), ".test_app")
]

Enum.each(cleanup_dirs, fn dir ->
  if File.exists?(dir) do
    IO.puts("Cleaning up directory: #{dir}")
    File.rm_rf!(dir)
  end
end)

# Register cleanup at the END of all tests
System.at_exit(fn _ ->
  Enum.each(cleanup_dirs, fn dir ->
    if File.exists?(dir) do
      IO.puts("Final cleanup of directory: #{dir}")
      File.rm_rf!(dir)
    end
  end)
end)

ExUnit.start()
