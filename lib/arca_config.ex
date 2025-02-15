defmodule Arca.Config do
  @moduledoc """
  Documentation for `Arca.Config`.
  """

  use Application

  @doc """
  Handle Application functionality to start the Arca.Config subsystem.
  """
  @impl true
  def start(_type, _args) do
    {:ok, self()}
  end

  @doc """
  Entry point for config.
  """
  def main(_argv) do
    :ok
  end
end
