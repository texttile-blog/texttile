defmodule Texttile.Boot do
  @moduledoc """
  Remembers when this node started.

  The first-run setup screen is only open for a limited time after the
  start (the way Portainer does it). That window needs one fact: the
  boot time. It lives in `:persistent_term` because it never changes
  while the node runs, and it is measured on the monotonic clock, so a
  stepping wall clock (NTP on a fresh VM) cannot move the window.
  """

  @key {__MODULE__, :started_at}

  @doc "Records the boot time. Called once from the application start."
  def record_start, do: :persistent_term.put(@key, System.monotonic_time(:millisecond))

  @doc """
  Milliseconds since boot. Without a recorded start the answer is
  "forever": the setup window fails closed, never open.
  """
  def uptime_ms do
    case :persistent_term.get(@key, nil) do
      nil -> :infinity
      started_at -> System.monotonic_time(:millisecond) - started_at
    end
  end

  @doc false
  # Test override: moves the boot time (monotonic milliseconds) so
  # window tests do not wait.
  def set_started_at(ms), do: :persistent_term.put(@key, ms)
end
