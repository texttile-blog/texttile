defmodule Texttile.Articles.LockTest do
  use ExUnit.Case, async: true

  alias Texttile.Articles.Lock

  # Each test gets its own lock process with short, test-sized timers.
  # The article id only names the process; no database is involved.
  defp start_lock(context, opts \\ []) do
    id = System.unique_integer([:positive])

    pid =
      start_supervised!(
        {Lock,
         Keyword.merge(
           [article_id: id, grace_ms: 60, idle_ms: 200, flush_ms: 60, pubsub: false],
           opts
         )}
      )

    Map.merge(context, %{id: id, lock: pid})
  end

  defp spawn_holder do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  describe "acquire" do
    setup :start_lock

    test "a free lock goes to whoever opens the text", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      assert %{user_id: 1} = Lock.state(id)
    end

    test "a held lock answers with the holder", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      other = spawn_holder()
      assert {:held, %{user_id: 1}} = Lock.acquire(id, 2, other)
    end

    # Whoever was in the text first goes on writing. Opening it a
    # second time takes it off nobody, and that holds for your own
    # other tab too: a second window used to steal the lock from the
    # first one silently, mid-sentence.
    test "the same user in a second tab does not take the lock along", %{id: id} do
      old_tab = spawn_holder()
      assert :ok = Lock.acquire(id, 1, old_tab)

      assert {:held, %{user_id: 1, pid: ^old_tab}} = Lock.acquire(id, 1, self())
      assert %{pid: ^old_tab} = Lock.state(id)
    end

    test "the same user's second tab can still take it over by hand", %{id: id} do
      old_tab = spawn_holder()
      assert :ok = Lock.acquire(id, 1, old_tab)

      # the old tab never answers the flush, so the timeout carries it
      assert :pending = Lock.takeover(id, 1, self())
      assert_receive {:lock_granted, ^id}, 500

      assert %{pid: pid} = Lock.state(id)
      assert pid == self()
    end

    test "two simultaneous requests: the first wins, the second is told", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      assert {:held, %{user_id: 1}} = Lock.acquire(id, 2, spawn_holder())
    end
  end

  describe "release" do
    setup :start_lock

    test "an explicit release frees the lock", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      assert :ok = Lock.release(id, self())
      assert Lock.state(id) == :free
    end

    test "a dead holder keeps the lock through the grace period", %{id: id, lock: lock} do
      holder = spawn_holder()
      assert :ok = Lock.acquire(id, 1, holder)
      ref = Process.monitor(holder)
      send(holder, :stop)
      assert_receive {:DOWN, ^ref, :process, ^holder, :normal}
      _ = :sys.get_state(lock)

      # inside the grace period the lock still reads as held
      assert %{user_id: 1} = Lock.state(id)

      # and after it, the lock is free
      Process.sleep(120)
      assert Lock.state(id) == :free
    end

    test "the same user reconnecting within the grace gets it back silently",
         %{id: id, lock: lock} do
      holder = spawn_holder()
      assert :ok = Lock.acquire(id, 1, holder)
      ref = Process.monitor(holder)
      send(holder, :stop)
      assert_receive {:DOWN, ^ref, :process, ^holder, :normal}
      _ = :sys.get_state(lock)

      assert :ok = Lock.acquire(id, 1, self())
      assert %{user_id: 1, pid: pid} = Lock.state(id)
      assert pid == self()
    end

    test "no keystroke for the idle timeout releases the lock", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      Process.sleep(120)
      Lock.ping(id, self())
      Process.sleep(120)
      # the ping pushed the idle window out
      assert %{user_id: 1} = Lock.state(id)
      Process.sleep(260)
      assert Lock.state(id) == :free
    end
  end

  describe "takeover" do
    setup :start_lock

    test "asks the holder to flush, then transfers", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      requester = self()

      task =
        Task.async(fn ->
          Lock.takeover(id, 2, self())

          receive do
            {:lock_granted, ^id} -> send(requester, :granted)
          end
        end)

      assert_receive {:lock_flush, ^id}
      Lock.flushed(id)
      assert_receive {:lock_taken, ^id, 2}
      assert_receive :granted
      assert %{user_id: 2} = Lock.state(id)
      Task.await(task)
    end

    test "an unreachable holder is not waited for past the flush timeout", %{id: id} do
      holder = spawn_holder()
      assert :ok = Lock.acquire(id, 1, holder)
      assert :pending = Lock.takeover(id, 2, self())
      assert_receive {:lock_granted, ^id}, 500
      assert %{user_id: 2} = Lock.state(id)
    end

    test "taking over a free lock just acquires it", %{id: id} do
      assert :ok = Lock.takeover(id, 2, self())
      assert %{user_id: 2} = Lock.state(id)
    end

    test "a second takeover while one is pending: the later asker wins", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())

      first = spawn_holder()
      assert :pending = Lock.takeover(id, 2, first)
      assert_receive {:lock_flush, ^id}

      assert :pending = Lock.takeover(id, 3, self())
      Lock.flushed(id)

      assert_receive {:lock_granted, ^id}
      assert %{user_id: 3} = Lock.state(id)
    end
  end

  describe "activity" do
    setup :start_lock

    test "pings move last_keystroke_at", %{id: id} do
      assert :ok = Lock.acquire(id, 1, self())
      %{last_keystroke_at: t0} = Lock.state(id)
      Process.sleep(15)
      Lock.ping(id, self())
      %{last_keystroke_at: t1} = Lock.state(id)
      assert DateTime.compare(t1, t0) == :gt
    end
  end
end
