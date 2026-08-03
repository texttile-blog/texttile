defmodule Texttile.AccountsTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts
  alias Texttile.Boot

  @window_ms 30 * 60 * 1000

  describe "setup_state/0" do
    test "is :open right after boot while no user exists" do
      Boot.set_started_at(System.monotonic_time(:millisecond))
      assert Accounts.setup_state() == :open
    end

    test "is :closed more than 30 minutes after boot" do
      Boot.set_started_at(System.monotonic_time(:millisecond) - @window_ms - 1)
      assert Accounts.setup_state() == :closed
    after
      Boot.set_started_at(System.monotonic_time(:millisecond))
    end

    test "is :done as soon as a user exists, regardless of the window" do
      user_fixture()
      assert Accounts.setup_state() == :done
    end
  end

  describe "create_first_admin/2" do
    setup do
      Boot.set_started_at(System.monotonic_time(:millisecond))
      :ok
    end

    test "creates the admin and sends the confirmation mail without the password" do
      attrs = %{username: "kb", email: "kb@example.org", password: "a long password"}

      assert {:ok, user} = Accounts.create_first_admin(attrs, site: "texttile.blog")
      assert user.username == "kb"
      assert user.email == "kb@example.org"
      assert Bcrypt.verify_pass("a long password", user.password_hash)
      refute user.password_hash =~ "a long password"

      assert_email_sent(fn email ->
        assert email.to == [{"kb", "kb@example.org"}]
        assert email.subject =~ "texttile.blog"
        assert email.text_body =~ "kb"
        assert email.text_body =~ "texttile.blog"
        refute email.text_body =~ "a long password"
        true
      end)
    end

    test "refuses a second admin" do
      user_fixture()
      attrs = valid_user_attributes()
      assert {:error, :done} = Accounts.create_first_admin(attrs, site: "x")
    end

    test "refuses outside the setup window" do
      Boot.set_started_at(System.monotonic_time(:millisecond) - @window_ms - 1)
      attrs = valid_user_attributes()
      assert {:error, :closed} = Accounts.create_first_admin(attrs, site: "x")
    after
      Boot.set_started_at(System.monotonic_time(:millisecond))
    end

    test "validates username, email and password" do
      assert {:error, changeset} =
               Accounts.create_first_admin(
                 %{username: "Not Valid!", email: "not-a-mail", password: "short"},
                 site: "x"
               )

      assert %{username: [_], email: [_], password: [_]} = errors_on(changeset)
    end

    test "normalizes username and email to lower case" do
      attrs = %{username: "KB", email: "KB@Example.ORG", password: "a long password"}
      assert {:ok, user} = Accounts.create_first_admin(attrs, site: "x")
      assert user.username == "kb"
      assert user.email == "kb@example.org"
    end
  end

  describe "authenticate_user/2" do
    test "returns the user for the right username and password" do
      user = user_fixture()
      assert {:ok, found} = Accounts.authenticate_user(user.username, valid_password())
      assert found.id == user.id
    end

    test "accepts the username in any case" do
      user = user_fixture(%{username: "kb"})
      assert {:ok, found} = Accounts.authenticate_user("KB", valid_password())
      assert found.id == user.id
    end

    test "rejects a wrong password" do
      user = user_fixture()
      assert :error = Accounts.authenticate_user(user.username, "wrong password!")
    end

    test "rejects an unknown username" do
      assert :error = Accounts.authenticate_user("nobody", valid_password())
    end
  end

  describe "sessions" do
    test "create_session/1 returns a token that finds the user" do
      user = user_fixture()
      token = Accounts.create_session(user)
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    test "get_user_by_session_token/1 returns nil for an unknown token" do
      assert Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32)) == nil
    end

    test "list_sessions/1 lists only the user's sessions, newest first" do
      user = user_fixture()
      other = user_fixture()
      t1 = Accounts.create_session(user)
      t2 = Accounts.create_session(user)
      _other = Accounts.create_session(other)

      sessions = Accounts.list_sessions(user)
      assert length(sessions) == 2
      assert Enum.map(sessions, & &1.token) == [t2, t1]
    end

    test "delete_session/1 ends exactly that session" do
      user = user_fixture()
      t1 = Accounts.create_session(user)
      t2 = Accounts.create_session(user)

      :ok = Accounts.delete_session(t1)
      assert Accounts.get_user_by_session_token(t1) == nil
      assert Accounts.get_user_by_session_token(t2).id == user.id
    end

    test "delete_sessions_except/2 keeps only the given session" do
      user = user_fixture()
      keep = Accounts.create_session(user)
      _t1 = Accounts.create_session(user)
      _t2 = Accounts.create_session(user)

      :ok = Accounts.delete_sessions_except(user, keep)
      assert [%{token: ^keep}] = Accounts.list_sessions(user)
    end

    test "an old token no longer signs anybody in and drops out of the list" do
      user = user_fixture()
      token = Accounts.create_session(user)

      too_old = DateTime.add(DateTime.utc_now(), -61, :day) |> DateTime.truncate(:second)

      Texttile.Repo.update_all(Texttile.Accounts.Session,
        set: [inserted_at: too_old]
      )

      assert Accounts.get_user_by_session_token(token) == nil
      assert Accounts.list_sessions(user) == []
    end
  end

  describe "profile updates" do
    test "update_username/2 changes the login name" do
      user = user_fixture()
      assert {:ok, user} = Accounts.update_username(user, "newname")
      assert user.username == "newname"
      assert {:ok, _} = Accounts.authenticate_user("newname", valid_password())
    end

    test "update_username/2 keeps login names unique, case-insensitively" do
      user_fixture(%{username: "kb"})
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_username(user, "KB")
      assert %{username: [_]} = errors_on(changeset)
    end

    test "update_username/2 rejects invalid names" do
      user = user_fixture()
      assert {:error, _} = Accounts.update_username(user, "")
      assert {:error, _} = Accounts.update_username(user, "has spaces")
    end

    test "update_display_name/2 accepts any text, including nothing" do
      user = user_fixture()
      assert {:ok, user} = Accounts.update_display_name(user, "Klaus")
      assert user.display_name == "Klaus"
      assert {:ok, user} = Accounts.update_display_name(user, "")
      assert Accounts.display_name(user) == user.username
    end

    test "display_name/1 falls back to the username for blank names" do
      user = user_fixture(%{username: "kb"})
      assert Accounts.display_name(user) == "kb"
      {:ok, user} = Accounts.update_display_name(user, "   ")
      assert Accounts.display_name(user) == "kb"
      {:ok, user} = Accounts.update_display_name(user, "Klaus")
      assert Accounts.display_name(user) == "Klaus"
    end

    test "update_email/2 changes and normalizes the address" do
      user = user_fixture()
      assert {:ok, user} = Accounts.update_email(user, "New@Example.ORG")
      assert user.email == "new@example.org"
    end

    test "update_email/2 keeps addresses unique" do
      user_fixture(%{email: "taken@example.org"})
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_email(user, "Taken@example.org")
      assert %{email: [_]} = errors_on(changeset)
    end

    test "update_email/2 rejects an invalid address" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_email(user, "not-a-mail")
      assert %{email: [_]} = errors_on(changeset)
    end

    test "update_password/3 needs the current password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_password(user, "wrong current!", "a brand new password")

      assert %{current_password: [_]} = errors_on(changeset)

      assert {:ok, user} =
               Accounts.update_password(user, valid_password(), "a brand new password")

      assert {:ok, _} = Accounts.authenticate_user(user.username, "a brand new password")
      assert :error = Accounts.authenticate_user(user.username, valid_password())
    end

    test "update_password/3 rejects a short new password" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_password(user, valid_password(), "short")
      assert %{password: [_]} = errors_on(changeset)
    end

    test "update_password/3 verifies against a fresh read, never a stale struct" do
      stale = user_fixture()

      assert {:ok, _} = Accounts.update_password(stale, valid_password(), "second password!")

      # the first password is history: a caller holding the old struct
      # cannot authorize with it any more
      assert {:error, changeset} =
               Accounts.update_password(stale, valid_password(), "third password!!")

      assert %{current_password: [_]} = errors_on(changeset)

      # the real current password works, stale struct or not
      assert {:ok, _} = Accounts.update_password(stale, "second password!", "third password!!")
      assert {:ok, _} = Accounts.authenticate_user(stale.username, "third password!!")
    end
  end
end
