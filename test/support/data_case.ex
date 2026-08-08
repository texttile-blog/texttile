defmodule Texttile.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Texttile.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Texttile.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Texttile.DataCase
    end
  end

  setup tags do
    Texttile.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Texttile.Repo, shared: not tags[:async])
    take_write_lock()
    restore_admin_users_afterwards()
    forget_open_editors()
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    # Registered last, so it runs first: the mail has to be gone before
    # the owner is.
    on_exit(&settle_mail_tasks/0)
  end

  @doc """
  Waits for the mail a test sent to leave the building.

  A comment hands its mail to a task of its own, so the reader who
  wrote it never waits for another server. A task still running when
  the sandbox owner goes holds a connection nobody owns any more, and
  the next test then meets a busy database instead of its own.
  """
  def settle_mail_tasks(timeout \\ 2_000) do
    Texttile.Comments.TaskSupervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        timeout -> Process.demonitor(ref, [:flush])
      end
    end)
  end

  @doc """
  Closes every editor the tests before this one left open.

  The document locks live beside the database, keyed by article id, and
  no sandbox rolls them back. The ids do roll back: after one test the
  next text is id 1 again. So a lock an editor of the last test still
  holds lands on a text of this one, which then looks open in an editor
  to anybody who asks - the importer, for one.
  """
  def forget_open_editors, do: Texttile.Articles.Lock.forget_all()

  @doc """
  Puts the configured admin usernames back after the test. Fixtures and
  tests write that list, and it lives in the application environment,
  which no sandbox rolls back.
  """
  def restore_admin_users_afterwards do
    admin_users = Application.get_env(:texttile, :admin_users)
    on_exit(fn -> Application.put_env(:texttile, :admin_users, admin_users) end)
  end

  @doc """
  Takes the SQLite write lock for the test that is starting.

  SQLite gives the write lock to one connection at a time. The sandbox opens a
  deferred transaction, which asks for the lock at the first write, and SQLite
  refuses to give it to a transaction that has read already: it answers
  "Database busy" at once, without waiting for the holder. A test therefore
  failed whenever another connection still held the lock, which happens when a
  process from the test before (a LiveView, an upload channel) dies in the
  middle of a write and its connection needs a moment to go down.

  Writing the database header before the test body turns the transaction into a
  writing one from the start. Tests now wait for each other here, for as long
  as `:busy_timeout` in `config/test.exs`, instead of failing halfway through.
  The write belongs to the sandbox transaction and rolls back with it.
  """
  def take_write_lock do
    Texttile.Repo.query!("PRAGMA user_version = 0")
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.claim_account("kb", %{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
