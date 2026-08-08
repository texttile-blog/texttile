defmodule Texttile.Comments.Sweeper do
  @moduledoc """
  Empties the comment trash: once an hour, and once on boot, whatever
  has served its 30 days goes for good. The boot sweep is what makes a
  restart forget nothing - a window that closed while the app was down
  is caught the next time it comes up.

  The gallery's sweeper arms a timer on the exact moment instead, and it
  has to: its undo window is ten seconds long. Thirty days needs no such
  aim, so this one just ticks.

  Stays out of tests like the go-live clock; the tests call
  `Texttile.Comments.sweep_due/0` directly.
  """
  use GenServer

  require Logger

  alias Texttile.Comments

  @every_ms :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :sweep}}
  end

  @impl true
  def handle_continue(:sweep, state) do
    {:noreply, sweep(state)}
  end

  @impl true
  def handle_info(:sweep, state) do
    {:noreply, sweep(state)}
  end

  defp sweep(state) do
    case Comments.sweep_due() do
      0 -> :ok
      count -> Logger.info("Comment trash: #{count} deleted for good")
    end

    Process.send_after(self(), :sweep, @every_ms)
    state
  end
end
