defmodule Texttile.AccountsTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  describe "sign_in_state/1" do
    test "is :claimable for a configured name that has no account yet" do
      configure_admins(["kb"])
      assert Accounts.sign_in_state("kb") == :claimable
    end

    test "is :known once the account exists" do
      user_fixture(%{username: "kb"})
      assert Accounts.sign_in_state("kb") == :known
    end

    test "is :unknown for a name that nobody configured" do
      configure_admins(["kb"])
      assert Accounts.sign_in_state("julia") == :unknown
    end

    # Taking a name out of the configuration takes the access away, even
    # though the account is still there.
    test "is :unknown for an account whose name left the configuration" do
      user_fixture(%{username: "kb"})
      configure_admins([])
      assert Accounts.sign_in_state("kb") == :unknown
    end

    test "reads the name the way people type it" do
      configure_admins(["kb"])
      assert Accounts.sign_in_state(" KB ") == :claimable
    end

    test "is :unknown while no name is configured at all" do
      configure_admins([])
      assert Accounts.sign_in_state("kb") == :unknown
    end
  end

  describe "claim_account/3" do
    test "creates the account of a configured name and signs it in from then on" do
      configure_admins(["kb"])

      assert {:ok, user} = Accounts.claim_account("kb", "a long password")
      assert user.username == "kb"
      assert Bcrypt.verify_pass("a long password", user.password_hash)
      assert {:ok, _} = Accounts.authenticate_user("kb", "a long password")
    end

    test "creates it without an email address, the profile fills that in" do
      configure_admins(["kb"])
      assert {:ok, user} = Accounts.claim_account("kb", "a long password")
      assert user.email == nil

      assert {:ok, user} = Accounts.update_email(user, "kb@example.org")
      assert user.email == "kb@example.org"
    end

    test "refuses a name that nobody configured" do
      configure_admins(["kb"])
      assert {:error, :not_allowed} = Accounts.claim_account("julia", "a long password")
      assert Accounts.sign_in_state("julia") == :unknown
    end

    test "refuses a name that already has an account" do
      user_fixture(%{username: "kb"})
      assert {:error, :taken} = Accounts.claim_account("kb", "another long password")
    end

    test "keeps the password rules and its confirmation" do
      configure_admins(["kb"])
      assert {:error, changeset} = Accounts.claim_account("kb", "short", "short")
      assert %{password: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Accounts.claim_account("kb", "a long password", "a long passwort")

      assert %{password_confirmation: [_]} = errors_on(changeset)
    end

    test "normalizes the name" do
      configure_admins(["kb"])
      assert {:ok, user} = Accounts.claim_account(" KB ", "a long password")
      assert user.username == "kb"
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

    test "rejects a user whose name left the configuration" do
      user = user_fixture()
      configure_admins([])
      assert :error = Accounts.authenticate_user(user.username, valid_password())
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

    # The open browser of somebody who left the configuration is out on
    # the next request, not only at the next sign-in.
    test "get_user_by_session_token/1 drops the session of a removed name" do
      user = user_fixture()
      token = Accounts.create_session(user)
      assert Accounts.get_user_by_session_token(token).id == user.id

      configure_admins([])
      assert Accounts.get_user_by_session_token(token) == nil
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
    test "update_username/2 changes the login name to another configured one" do
      user = user_fixture()
      configure_admins([user.username, "newname"])

      assert {:ok, user} = Accounts.update_username(user, "newname")
      assert user.username == "newname"
      assert {:ok, _} = Accounts.authenticate_user("newname", valid_password())
    end

    # Renaming yourself to a name the configuration does not carry would
    # sign you out of your own account on the next request.
    test "update_username/2 refuses a name that is not configured" do
      user = user_fixture()

      assert {:error, changeset} = Accounts.update_username(user, "stranger")
      assert %{username: ["is not a username this server allows"]} = errors_on(changeset)
      assert {:ok, _} = Accounts.authenticate_user(user.username, valid_password())
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

  describe "delete_user/2" do
    test "deletes another account with its sessions" do
      me = user_fixture(%{username: "kb"})
      other = user_fixture(%{username: "julia"})
      Accounts.create_session(other)

      assert {:ok, _} = Accounts.delete_user(other, by: me)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(other.id) end
      assert Accounts.list_sessions(other) == []
    end

    test "never you, never the last account" do
      me = user_fixture(%{username: "kb"})
      assert {:error, :last} = Accounts.delete_user(me, by: me)

      other = user_fixture(%{username: "julia"})
      assert {:error, :yourself} = Accounts.delete_user(other, by: other)
    end

    test "an account another admin deleted first answers :gone, not a crash" do
      me = user_fixture(%{username: "kb"})
      other = user_fixture(%{username: "julia"})
      _third = user_fixture(%{username: "pat"})

      {:ok, _} = Accounts.delete_user(other, by: me)
      assert {:error, :gone} = Accounts.delete_user(other, by: me)
    end
  end

  describe "list_users/0" do
    test "everybody, oldest account first" do
      kb = user_fixture(%{username: "kb"})
      julia = user_fixture(%{username: "julia"})

      assert Enum.map(Accounts.list_users(), & &1.id) == [kb.id, julia.id]
    end
  end
end
