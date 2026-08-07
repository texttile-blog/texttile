defmodule Texttile.Comments.RateLimiter do
  @moduledoc """
  The third invisible spam filter: one caller may send a few comments a
  minute, no more. A sliding window per key in one ETS table, pruned as
  it is read - no external store, no cookie, nothing kept but a handful
  of timestamps that expire within the minute.
  """

  use GenServer

  @limit 3
  @window_ms 60_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc """
  Whether the key (in practice: the reader's IP) may send another
  comment now. Counting and answering is one atomic step in the server,
  so two racing requests never share a free slot.
  """
  def allow?(key, name \\ __MODULE__) do
    GenServer.call(name, {:allow?, key})
  end

  @impl true
  def init(name) do
    table = :ets.new(name, [:set, :private])
    {:ok, table}
  end

  @impl true
  def handle_call({:allow?, key}, _from, table) do
    now = System.monotonic_time(:millisecond)

    recent =
      case :ets.lookup(table, key) do
        [{^key, stamps}] -> Enum.filter(stamps, &(now - &1 < @window_ms))
        [] -> []
      end

    if length(recent) < @limit do
      :ets.insert(table, {key, [now | recent]})
      {:reply, true, table}
    else
      :ets.insert(table, {key, recent})
      {:reply, false, table}
    end
  end
end
