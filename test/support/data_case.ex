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
    clear_what_no_sandbox_rolls_back()
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    # Registered last, so it runs first: the mail has to be gone before
    # the owner is.
    on_exit(&settle_mail_tasks/0)
  end

  @doc """
  Clears everything a test can leave behind that the sandbox does not
  roll back, and arranges for this test's own leavings to go too.

  The database rolls back by itself. These do not: the application
  environment, the edit locks, the uploaded files, the rate limiter's
  table, the import job and where the mail lands. Every one of them
  used to be cleared by hand in the tests that happened to need it,
  which is how a test that needed it and did not say so became a test
  that fails only after some other test.

  The browser tests keep their own sandbox and never pass through
  `setup_sandbox/1`, so they call this themselves.
  """
  def clear_what_no_sandbox_rolls_back do
    restore_admin_users_afterwards()
    forget_open_editors()
    clear_uploads()
    Texttile.RateLimiter.reset()
    Texttile.RateLimiter.reset(Texttile.Backup.limiter())
    Texttile.RateLimiter.reset(Texttile.Accounts.door_limiter())
    catch_mail()

    on_exit(fn ->
      Texttile.Import.Job.discard()
      clear_uploads()
    end)

    :ok
  end

  @doc """
  Takes the uploaded files of the test before this one. They live below
  one root that `config/test.exs` points into `tmp/`, never at the
  user's own uploads.

  The walk can lose a folder it has just emptied. `File.rm_rf/1` lists a
  folder, removes what it listed, and then asks for the folder itself; a
  rendition request that the browser gave up on writes a moment longer
  than the test that started it, so a file lands in between. The system
  call answers ENOTEMPTY, which Erlang reports as `:eexist`, and the
  bang form raises in a teardown callback. That is not a broken cleanup
  but a writer that has not finished, so the walk starts again. It gives
  up after two seconds, because a root that stays busy that long means
  something bigger is wrong than one late file.
  """
  @busy_timeout 2_000

  def clear_uploads, do: clear_uploads(System.monotonic_time(:millisecond) + @busy_timeout)

  defp clear_uploads(deadline) do
    case File.rm_rf(Texttile.Uploads.root()) do
      {:ok, _removed} ->
        :ok

      {:error, reason, path} when reason in [:eexist, :enotempty] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          clear_uploads(deadline)
        else
          raise_cleanup_error(reason, path)
        end

      {:error, reason, path} ->
        raise_cleanup_error(reason, path)
    end
  end

  defp raise_cleanup_error(reason, path) do
    raise File.Error,
      reason: reason,
      path: path,
      action: "remove files and directories recursively from"
  end

  @doc """
  Sends every mail of this test to this test, whichever process wrote
  it. A comment and a text going live both hand their mail to a task,
  and a task delivers to nobody unless somebody says where.
  """
  def catch_mail do
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
    :ok
  end

  @doc """
  Runs `fun` until it answers something other than nil or false, and
  gives up after `timeout` ms.

  For the things that settle a moment after the click: an autosave
  behind its debounce, a broadcast on its way, a conversion in the
  queue. Six copies of this stood in six test files.
  """
  def eventually(fun, timeout \\ 3_000) do
    wait_until(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp wait_until(fun, deadline) do
    case fun.() do
      answer when answer not in [nil, false] ->
        answer

      _not_yet ->
        if System.monotonic_time(:millisecond) > deadline do
          raise "waited for something that never happened"
        end

        Process.sleep(50)
        wait_until(fun, deadline)
    end
  end

  @doc """
  Waits for the mail a test sent to leave the building.

  A comment hands its mail to a task of its own, so the reader who
  wrote it never waits for another server, and an entry going live
  hands the list to another. A task still running when the sandbox
  owner goes holds a connection nobody owns any more, and the next test
  then meets a busy database instead of its own.

  Both supervisors are waited for. Watching only one is how this bites:
  the other task runs on, and what it says arrives as a stray error on
  a test that has nothing to do with it.
  """
  @mail_supervisors [Texttile.Comments.TaskSupervisor, Texttile.Newsletter.TaskSupervisor]

  def settle_mail_tasks(timeout \\ 2_000) do
    @mail_supervisors
    |> Enum.flat_map(&Task.Supervisor.children/1)
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
