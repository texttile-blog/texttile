defmodule Texttile.Articles.EditingTest do
  # The lock lives beside the database, not in it, and this asks it
  # questions. No database is involved.
  use ExUnit.Case, async: true

  alias Texttile.Articles.Editing
  alias Texttile.Articles.Lock

  defp start_lock(context) do
    id = System.unique_integer([:positive])

    start_supervised!(
      {Lock, article_id: id, grace_ms: 60, idle_ms: 200, flush_ms: 60, pubsub: false}
    )

    Map.put(context, :id, id)
  end

  defp other_tab do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  setup :start_lock

  describe "start/3" do
    test "a free entry is opened for writing", %{id: id} do
      editing = Editing.start(id, 1, self())

      assert Editing.writing?(editing)
      assert Editing.holds?(editing)
      refute Editing.read_only?(editing)
      assert Editing.holder(editing) == nil
    end

    test "an entry somebody else holds is opened for watching", %{id: id} do
      Lock.acquire(id, 1, other_tab())

      editing = Editing.start(id, 2, self())

      refute Editing.holds?(editing)
      assert Editing.read_only?(editing)
      assert %{user_id: 1} = Editing.holder(editing)
    end
  end

  describe "who_holds/2" do
    test "answers from this tab's own side", %{id: id} do
      assert Editing.who_holds(id, self()) == :free

      Lock.acquire(id, 1, self())
      assert Editing.who_holds(id, self()) == :mine

      other = other_tab()
      Lock.release(id, self())
      Lock.acquire(id, 2, other)
      assert {:held, %{user_id: 2}} = Editing.who_holds(id, self())
    end
  end

  describe "flushing" do
    test "a flushing tab still holds the entry, and writes again after", %{id: id} do
      editing = Editing.start(id, 1, self()) |> Editing.flushing()

      assert Editing.flushing?(editing)
      assert Editing.holds?(editing)
      refute Editing.read_only?(editing)

      assert Editing.flushed(editing) |> Editing.writing?()
    end

    test "a watching tab is not asked to flush", %{id: id} do
      Lock.acquire(id, 1, other_tab())
      editing = Editing.start(id, 2, self())

      refute editing |> Editing.flushing() |> Editing.flushing?()
    end
  end

  describe "refresh/4" do
    test "a tab that was watching takes a free entry", %{id: id} do
      other = other_tab()
      Lock.acquire(id, 1, other)
      editing = Editing.start(id, 2, self())
      refute Editing.holds?(editing)

      Lock.release(id, other)

      assert Editing.refresh(editing, id, 2, self()) |> Editing.writing?()
    end

    # Taking it straight back would undo the release, forever.
    test "a tab that was just released for idling does not take it back", %{id: id} do
      editing = Editing.start(id, 1, self())
      assert Editing.writing?(editing)

      Lock.release(id, self())

      refreshed = Editing.refresh(editing, id, 1, self())
      refute Editing.holds?(refreshed)
      assert Editing.holder(refreshed) == nil
      assert Editing.who_holds(id, self()) == :free
    end

    test "a tab somebody took over from is told who has it now", %{id: id} do
      editing = Editing.start(id, 1, self())
      Lock.release(id, self())
      Lock.acquire(id, 2, other_tab())

      refreshed = Editing.refresh(editing, id, 1, self())

      refute Editing.holds?(refreshed)
      assert %{user_id: 2} = Editing.holder(refreshed)
    end
  end
end
