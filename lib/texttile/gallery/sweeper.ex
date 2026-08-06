defmodule Texttile.Gallery.Sweeper do
  @moduledoc """
  Makes gallery deletions final once their undo window has closed. One
  timer for the next due moment, re-read from the database after every
  sweep, so a restart forgets nothing: whatever came due while the app
  was down is swept on boot.

  Stays out of tests like the go-live clock; the tests call
  `Texttile.Gallery.sweep_due/0` directly.
  """
  use GenServer

  alias Texttile.Gallery

  # A breath after the deadline, so a sweep never fires a hair early.
  @slack_ms 200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Tells the sweeper a deletion is pending. Safe when it is not running."
  def schedule(%DateTime{} = delete_after) do
    GenServer.cast(__MODULE__, {:pending, delete_after})
  end

  @impl true
  def init(_opts) do
    {:ok, %{timer: nil, at: nil}, {:continue, :sweep}}
  end

  @impl true
  def handle_continue(:sweep, state) do
    {:noreply, sweep_and_rearm(state)}
  end

  @impl true
  def handle_cast({:pending, at}, state) do
    {:noreply, arm(state, at)}
  end

  @impl true
  def handle_info(:sweep, state) do
    {:noreply, sweep_and_rearm(%{state | timer: nil, at: nil})}
  end

  defp sweep_and_rearm(state) do
    Gallery.sweep_due()

    case Gallery.next_due() do
      nil -> state
      at -> arm(state, at)
    end
  end

  # Keeps the earlier of the armed moment and the new one.
  defp arm(%{at: current} = state, at) do
    if current && DateTime.compare(current, at) != :gt do
      state
    else
      if state.timer, do: Process.cancel_timer(state.timer)
      delay = max(DateTime.diff(at, DateTime.utc_now(), :millisecond), 0) + @slack_ms
      %{state | timer: Process.send_after(self(), :sweep, delay), at: at}
    end
  end
end
