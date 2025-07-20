# Load environment variables from .env file early in the configuration process
# This file is imported by config.exs to ensure env vars are available
# for runtime.exs and other configuration files

env_file = Path.join([File.cwd!(), "config", ".env"])

if File.exists?(env_file) do
  # Parse and load environment variables manually
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    # Skip empty lines and comments
    if line != "" && !String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          # Remove quotes if present
          value = String.trim(value, "\"")
          System.put_env(String.trim(key), value)

        _ ->
          :ok
      end
    end
  end)
end
