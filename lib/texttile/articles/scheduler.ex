defmodule Texttile.Articles.Scheduler do
  @moduledoc """
  The clock behind scheduled texts: every few minutes it asks
  `Texttile.Articles.go_live_due/1` whether a scheduled day has come,
  and the texts that are due go live. The subscriber email, once the
  newsletter exists, hooks in here and only here.

  Not started in tests; the tests call `go_live_due/1` directly.
  """

  use GenServer

  @tick_ms 5 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, schedule(%{})}
  end

  @impl true
  def handle_info(:tick, state) do
    Texttile.Articles.go_live_due()
    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    Process.send_after(self(), :tick, @tick_ms)
    state
  end
end
