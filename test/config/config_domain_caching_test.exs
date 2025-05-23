defmodule Arca.Config.ConfigDomainCachingTest do
  use ExUnit.Case, async: false

  setup do
    # Clear any existing cache and application config before each test
    Arca.Config.Cfg.clear_domain_cache()
    Application.delete_env(:arca_config, :config_domain)

    on_exit(fn ->
      # Clean up after each test
      Arca.Config.Cfg.clear_domain_cache()
      Application.delete_env(:arca_config, :config_domain)
    end)
  end

  test "config_domain/0 prioritizes explicit Application config over cached values" do
    # First call should use auto-detection and cache the result
    _auto_detected_domain = Arca.Config.Cfg.config_domain()

    # Set explicit config - should take precedence immediately
    Application.put_env(:arca_config, :config_domain, :test_app)
    domain2 = Arca.Config.Cfg.config_domain()
    assert domain2 == :test_app

    # Change explicit config - should change immediately (no caching of explicit config)
    Application.put_env(:arca_config, :config_domain, :another_app)
    domain3 = Arca.Config.Cfg.config_domain()
    assert domain3 == :another_app
  end

  test "config_domain/0 falls back to cached auto-detection when explicit config is removed" do
    # First get the auto-detected domain to know what to expect
    auto_detected_domain = Arca.Config.Cfg.config_domain()

    # Set and then remove explicit config
    Application.put_env(:arca_config, :config_domain, :test_app)
    assert Arca.Config.Cfg.config_domain() == :test_app

    Application.delete_env(:arca_config, :config_domain)

    # Should fall back to cached auto-detection
    domain = Arca.Config.Cfg.config_domain()
    assert domain == auto_detected_domain
  end

  test "clear_domain_cache/0 forces re-evaluation of auto-detected domain" do
    # Get domain to populate cache
    domain1 = Arca.Config.Cfg.config_domain()

    # Clear cache
    result = Arca.Config.Cfg.clear_domain_cache()
    assert result == :ok

    # Next call should re-evaluate (though result may be the same)
    domain2 = Arca.Config.Cfg.config_domain()
    # Should still be the same auto-detected domain
    assert domain2 == domain1
  end

  test "explicit config takes precedence even after cache is populated" do
    # First call populates cache with auto-detected value
    domain1 = Arca.Config.Cfg.config_domain()
    # Store the auto-detected value
    auto_detected_domain = domain1

    # Setting explicit config should override cached value immediately
    Application.put_env(:arca_config, :config_domain, :override_app)
    domain2 = Arca.Config.Cfg.config_domain()
    assert domain2 == :override_app

    # Removing explicit config should fall back to cached value
    Application.delete_env(:arca_config, :config_domain)
    domain3 = Arca.Config.Cfg.config_domain()
    assert domain3 == auto_detected_domain
  end

  test "multiple calls to config_domain/0 with explicit config don't create cache pollution" do
    # Set explicit config
    Application.put_env(:arca_config, :config_domain, :consistent_app)

    # Multiple calls should return the same value
    domain1 = Arca.Config.Cfg.config_domain()
    domain2 = Arca.Config.Cfg.config_domain()
    domain3 = Arca.Config.Cfg.config_domain()

    assert domain1 == :consistent_app
    assert domain2 == :consistent_app
    assert domain3 == :consistent_app

    # Change explicit config
    Application.put_env(:arca_config, :config_domain, :new_app)
    domain4 = Arca.Config.Cfg.config_domain()
    assert domain4 == :new_app
  end
end
