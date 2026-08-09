defmodule Texttile.Articles.Lock do
  @moduledoc """
  The soft document lock: one process per open article owns who may
  write the title and the body. All lock operations go through it, so
  message ordering gives mutual exclusion for free; no database
  locking, no retries.

  Releasing has three paths, and all three live here:

    1. explicit, when the editor closes or navigates away;
    2. process death, with a grace period so a reload or a short
       network drop does not cost the lock;
    3. an idle timeout, so a forgotten tab hands the text over without
       anybody having to take it.

  The takeover asks the holder to flush first: the holder's LiveView
  gets `{:lock_flush, article_id}`, saves what is still in flight,
  snapshots a version and calls `flushed/1`; only then does the lock
  transfer. A holder that does not answer within the flush timeout is
  not waited for.

  Messages to the LiveViews involved:

    * `{:lock_flush, article_id}` — to the holder: flush, then `flushed/1`
    * `{:lock_taken, article_id, by_user_id}` — to the displaced holder
    * `{:lock_granted, article_id}` — to whoever just got the lock
    * `{:lock_changed, article_id}` — on the article's PubSub topic
  """

  use GenServer, restart: :temporary

  @registry __MODULE__.Registry
  @supervisor __MODULE__.Supervisor

  @grace_ms 45_000
  @idle_ms 15 * 60 * 1000
  @flush_ms 3_000

  ## API

  def registry, do: @registry
  def supervisor, do: @supervisor

  def start_link(opts) do
    article_id = Keyword.fetch!(opts, :article_id)
    GenServer.start_link(__MODULE__, opts, name: via(article_id))
  end

  defp via(article_id), do: {:via, Registry, {@registry, article_id}}

  @doc """
  Every text is free again: each lock process is stopped, whoever held
  it. The locks live beside the database, not in it, so nothing rolls
  them back - a test starts from no open editors with this.
  """
  def forget_all do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@supervisor), is_pid(pid) do
      DynamicSupervisor.terminate_child(@supervisor, pid)
    end

    :ok
  end

  @doc "The lock process of an article, started if it is not running."
  def ensure(article_id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, article_id: article_id}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @doc """
  Opening the text: a free lock is yours, a held one answers with the
  holder, and that holds for your own second tab as well. Whoever was
  in the text first goes on writing; everybody who arrives after them
  takes it over by hand or not at all.

  The one exception is the same user coming back to a tab that is
  gone: a reload or a short drop inside the grace hands the lock
  straight back, which is what the grace is for.
  """
  def acquire(article_id, user_id, pid) do
    GenServer.call(ensure(article_id), {:acquire, user_id, pid})
  end

  @doc "The holder's state, or :free. Feeds the banner and the takeover dialog."
  def state(article_id) do
    case Registry.lookup(@registry, article_id) do
      [{pid, _}] -> GenServer.call(pid, :state)
      [] -> :free
    end
  end

  @doc "Take the text over. Returns :ok when it was free, :pending while the holder flushes."
  def takeover(article_id, user_id, pid) do
    GenServer.call(ensure(article_id), {:takeover, user_id, pid})
  end

  @doc "The holder finished flushing; the transfer may go ahead."
  def flushed(article_id) do
    GenServer.cast(ensure(article_id), :flushed)
  end

  @doc "A keystroke: feeds the idle rule and the takeover dialog."
  def ping(article_id, pid) do
    GenServer.cast(ensure(article_id), {:ping, pid})
  end

  @doc "The editor closed or navigated away."
  def release(article_id, pid) do
    GenServer.call(ensure(article_id), {:release, pid})
  end

  ## GenServer

  @impl true
  def init(opts) do
    {:ok,
     %{
       article_id: Keyword.fetch!(opts, :article_id),
       grace_ms: Keyword.get(opts, :grace_ms, @grace_ms),
       idle_ms: Keyword.get(opts, :idle_ms, @idle_ms),
       flush_ms: Keyword.get(opts, :flush_ms, @flush_ms),
       pubsub: Keyword.get(opts, :pubsub, true),
       holder: nil,
       grace_timer: nil,
       idle_timer: nil,
       pending: nil
     }}
  end

  @impl true
  def handle_call({:acquire, user_id, pid}, _from, state) do
    cond do
      state.holder == nil ->
        {:reply, :ok, give(state, user_id, pid)}

      # the same person coming back to a tab that is not there any
      # more: a reload, a short drop, a window closed inside the grace
      state.holder.user_id == user_id and gone?(state.holder, state) ->
        {:reply, :ok, give(drop_holder(state), user_id, pid)}

      true ->
        {:reply, {:held, public(state.holder)}, state}
    end
  end

  def handle_call(:state, _from, state) do
    {:reply, if(state.holder, do: public(state.holder), else: :free), state}
  end

  def handle_call({:release, pid}, _from, state) do
    if state.holder && state.holder.pid == pid do
      {:reply, :ok, state |> drop_holder() |> announce()}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:takeover, user_id, pid}, _from, state) do
    cond do
      state.holder == nil ->
        {:reply, :ok, give(state, user_id, pid)}

      # A tab that is gone has nothing left to flush. A tab that is
      # still there does, and whose tab it is makes no difference to
      # the words that are still in flight in it.
      state.holder.user_id == user_id and gone?(state.holder, state) ->
        {:reply, :ok, give(drop_holder(state), user_id, pid)}

      state.pending != nil ->
        {:reply, :pending, %{state | pending: %{state.pending | user_id: user_id, pid: pid}}}

      true ->
        send(state.holder.pid, {:lock_flush, state.article_id})
        timer = Process.send_after(self(), :flush_timeout, state.flush_ms)
        {:reply, :pending, %{state | pending: %{user_id: user_id, pid: pid, timer: timer}}}
    end
  end

  @impl true
  def handle_cast(:flushed, state), do: {:noreply, transfer(state)}

  def handle_cast({:ping, pid}, state) do
    if state.holder && state.holder.pid == pid do
      holder = %{state.holder | last_keystroke_at: DateTime.utc_now()}
      {:noreply, reset_idle(%{state | holder: holder})}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush_timeout, state), do: {:noreply, transfer(state)}

  def handle_info(:grace_over, state) do
    {:noreply, state |> drop_holder() |> announce()}
  end

  def handle_info(:idle_over, state) do
    {:noreply, state |> drop_holder() |> announce()}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if state.holder && state.holder.ref == ref do
      timer = Process.send_after(self(), :grace_over, state.grace_ms)
      {:noreply, %{state | grace_timer: timer}}
    else
      {:noreply, state}
    end
  end

  ## The moves

  # Opening a text never takes it off anybody, not even off yourself:
  # whoever was there first goes on writing, and everybody after them
  # asks. Only a holder whose tab is gone leaves the lock behind.
  defp gone?(holder, state), do: state.grace_timer != nil or not Process.alive?(holder.pid)

  defp give(state, user_id, pid) do
    now = DateTime.utc_now()

    holder = %{
      user_id: user_id,
      pid: pid,
      ref: Process.monitor(pid),
      acquired_at: now,
      last_keystroke_at: now
    }

    %{state | holder: holder}
    |> cancel(:grace_timer)
    |> reset_idle()
    |> announce()
  end

  # The transfer itself, after the flush answered or timed out. Without
  # a pending requester (a stray :flush_timeout) there is nothing to do.
  defp transfer(%{pending: nil} = state), do: state

  defp transfer(state) do
    %{user_id: user_id, pid: pid, timer: timer} = state.pending
    Process.cancel_timer(timer)

    if state.holder, do: send(state.holder.pid, {:lock_taken, state.article_id, user_id})
    send(pid, {:lock_granted, state.article_id})

    state
    |> drop_holder()
    |> Map.put(:pending, nil)
    |> give(user_id, pid)
  end

  defp drop_holder(state) do
    if state.holder, do: Process.demonitor(state.holder.ref, [:flush])

    %{state | holder: nil}
    |> cancel(:grace_timer)
    |> cancel(:idle_timer)
  end

  defp reset_idle(state) do
    state = cancel(state, :idle_timer)
    %{state | idle_timer: Process.send_after(self(), :idle_over, state.idle_ms)}
  end

  defp cancel(state, key) do
    if timer = Map.get(state, key), do: Process.cancel_timer(timer)
    Map.put(state, key, nil)
  end

  defp announce(state) do
    if state.pubsub do
      Phoenix.PubSub.broadcast(
        Texttile.PubSub,
        "article:#{state.article_id}",
        {:lock_changed, state.article_id}
      )
    end

    state
  end

  defp public(holder), do: Map.take(holder, [:user_id, :pid, :acquired_at, :last_keystroke_at])
end
