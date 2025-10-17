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
    # Suppress output during test setup
    File.rm_rf!(dir)
  end
end)

# Register cleanup at the END of all tests
System.at_exit(fn _ ->
  Enum.each(cleanup_dirs, fn dir ->
    if File.exists?(dir) do
      # Suppress output during test cleanup
      File.rm_rf!(dir)
    end
  end)
end)

ExUnit.start()
