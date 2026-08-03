defmodule Texttile.Boot do
  @moduledoc """
  Remembers when this node started.

  The first-run setup screen is only open for a limited time after the
  start (the way Portainer does it). That window needs one fact: the
  boot time. It lives in `:persistent_term` because it never changes
  while the node runs.
  """

  @key {__MODULE__, :started_at}

  @doc "Records the boot time. Called once from the application start."
  def record_start, do: :persistent_term.put(@key, System.system_time(:millisecond))

  @doc "Milliseconds since boot."
  def uptime_ms, do: System.system_time(:millisecond) - started_at()

  defp started_at, do: :persistent_term.get(@key, System.system_time(:millisecond))

  @doc false
  # Test override: moves the boot time so window tests do not wait.
  def set_started_at(ms), do: :persistent_term.put(@key, ms)
end
