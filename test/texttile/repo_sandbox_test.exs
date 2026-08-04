defmodule Texttile.RepoSandboxTest do
  @moduledoc """
  Guards the write lock that `Texttile.DataCase.take_write_lock/0` takes for
  every test. Without it, a test that reads before it writes fails with
  "Database busy" as soon as another connection holds the lock, and CI saw
  exactly that.
  """
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Accounts.User

  # Asks for the write lock from outside the pool, without waiting.
  defp lock_free? do
    {:ok, db} = Exqlite.Sqlite3.open(Application.get_env(:texttile, Texttile.Repo)[:database])
    :ok = Exqlite.Sqlite3.execute(db, "PRAGMA busy_timeout = 0")
    outcome = Exqlite.Sqlite3.execute(db, "BEGIN IMMEDIATE")
    if outcome == :ok, do: :ok = Exqlite.Sqlite3.execute(db, "ROLLBACK")
    :ok = Exqlite.Sqlite3.close(db)

    outcome == :ok
  end

  test "a test holds the write lock before it touches the database" do
    refute lock_free?()
  end

  test "a write still works after a read in the same test" do
    assert Repo.aggregate(User, :count) >= 0
    assert %User{} = user_fixture()
  end
end
