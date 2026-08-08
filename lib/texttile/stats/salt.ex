defmodule Texttile.Stats.Salt do
  @moduledoc """
  The secret that turns a reader into a number for one day.

  It is random, it lives in this process and nowhere else, and it is
  replaced when the day turns. So a visitor hash means "the same
  reader, today", and tomorrow the same reader hashes to something
  else. Nothing on disk can ever be traced back to an address, because
  the only thing that could do it is gone.

  A restart makes a new salt early. That splits one reader into two for
  the rest of the day, which is the direction to err in.
  """

  use GenServer

  @check_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The salt of today, as raw bytes."
  def current(name \\ __MODULE__), do: GenServer.call(name, :current)

  @doc "Throws the salt away and draws a new one. The day turn, by hand."
  def roll(name \\ __MODULE__), do: GenServer.call(name, :roll)

  @impl true
  def init(:ok) do
    :timer.send_interval(@check_ms, :check_day)
    {:ok, fresh()}
  end

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state.salt, state}

  def handle_call(:roll, _from, _state), do: {:reply, :ok, fresh()}

  @impl true
  def handle_info(:check_day, state) do
    if Date.utc_today() == state.day, do: {:noreply, state}, else: {:noreply, fresh()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp fresh, do: %{day: Date.utc_today(), salt: :crypto.strong_rand_bytes(32)}
end
