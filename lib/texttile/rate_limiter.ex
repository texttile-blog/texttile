defmodule Texttile.RateLimiter do
  @moduledoc """
  The third invisible spam filter of the public forms: one caller may
  knock a few times a minute, no more - comments and newsletter
  requests out of one bucket. A sliding window per key in one ETS
  table, pruned as it is read and swept once a minute - no external
  store, no cookie, nothing kept but timestamps that expire within the
  minute.

  A second one of these stands in front of the view counter, with a
  wider limit: a reader turns pages faster than they write comments,
  and what it has to stop is a caller writing rows all day.
  """

  use GenServer

  @limit 3
  @window_ms 60_000
  @sweep_ms 60_000

  @doc """
  Starts a limiter. `name:` gives it one of its own, `limit:` how many
  knocks a caller has in the minute.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    limit = Keyword.get(opts, :limit, @limit)
    GenServer.start_link(__MODULE__, {name, limit}, name: name)
  end

  @doc "A child spec per name, so two limiters can stand side by side."
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Whether the key (in practice: the reader's IP) may knock again now.
  Counting and answering is one atomic step in the server, so two
  racing requests never share a free slot.
  """
  def allow?(key, name \\ __MODULE__) do
    GenServer.call(name, {:allow?, key})
  end

  @doc """
  Forgets every window. One test's requests must not count against the
  next one's: every caller in a test run wears the same address.
  """
  def reset(name \\ __MODULE__) do
    GenServer.call(name, :reset)
  end

  @impl true
  def init({name, limit}) do
    table = :ets.new(name, [:set, :private])
    :timer.send_interval(@sweep_ms, :sweep)
    {:ok, %{table: table, limit: limit}}
  end

  # A key nobody asks about again would sit here forever, and the keys
  # come from the outside: without this sweep the table is a place a
  # caller can make grow. Every window that has run out goes.
  @impl true
  def handle_info(:sweep, %{table: table} = state) do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {key, stamps}, acc ->
        if Enum.any?(stamps, &(now - &1 < @window_ms)), do: acc, else: [key | acc]
      end,
      [],
      table
    )
    |> Enum.each(&:ets.delete(table, &1))

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:reset, _from, %{table: table} = state) do
    :ets.delete_all_objects(table)
    {:reply, :ok, state}
  end

  def handle_call({:allow?, key}, _from, %{table: table, limit: limit} = state) do
    now = System.monotonic_time(:millisecond)

    recent =
      case :ets.lookup(table, key) do
        [{^key, stamps}] -> Enum.filter(stamps, &(now - &1 < @window_ms))
        [] -> []
      end

    if length(recent) < limit do
      :ets.insert(table, {key, [now | recent]})
      {:reply, true, state}
    else
      :ets.insert(table, {key, recent})
      {:reply, false, state}
    end
  end
end
