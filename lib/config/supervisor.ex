defmodule Arca.Config.Supervisor do
  @moduledoc """
  Supervisor for Arca.Config components.

  Manages the lifecycle of the configuration server and its dependencies,
  including registries for configuration subscriptions and callbacks.
  Configuration loading is handled through OTP start phases.
  """

  use Supervisor

  @doc """
  Starts the Arca.Config supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for configuration subscriptions
      {Registry,
       keys: :duplicate, name: Arca.Config.Registry, partitions: System.schedulers_online()},

      # Registry for external change callbacks
      {Registry, keys: :duplicate, name: Arca.Config.CallbackRegistry},

      # Registry for simple 0-arity callbacks
      {Registry, keys: :duplicate, name: Arca.Config.SimpleCallbackRegistry},

      # ETS-based cache owner process for configuration values
      Arca.Config.Cache,

      # Main configuration server
      {Arca.Config.Server, []},

      # File watcher process for detecting external changes
      Arca.Config.FileWatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
