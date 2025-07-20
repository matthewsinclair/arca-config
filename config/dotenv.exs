# Manual .env file loader for dev and test environments
# This avoids using Mix in runtime code
if Mix.env() in [:dev, :test] do
  env_file = Path.join([File.cwd!(), "config", ".env"])
  
  if File.exists?(env_file) do
    env_file
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)
      
      if line != "" && !String.starts_with?(line, "#") do
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            # Trim quotes from value if present
            value = String.trim(value, "\"")
            System.put_env(String.trim(key), value)
            
          _ ->
            :ok
        end
      end
    end)
  end
end