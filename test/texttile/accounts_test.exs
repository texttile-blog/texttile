defmodule Texttile.AccountsTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
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

      attrs = %{password: "a long password", email: "kb@example.org", display_name: "KB"}
      assert {:ok, user} = Accounts.claim_account("kb", attrs)
      assert user.username == "kb"
      assert user.email == "kb@example.org"
      assert user.display_name == "KB"
      assert Bcrypt.verify_pass("a long password", user.password_hash)
      assert {:ok, _} = Accounts.authenticate_user("kb", "a long password")
    end

    # The address is what a password reset needs, so an account never
    # exists without one.
    test "refuses to create an account without an email address" do
      configure_admins(["kb"])

      assert {:error, changeset} = Accounts.claim_account("kb", %{password: "a long password"})
      assert %{email: [_]} = errors_on(changeset)
      assert Accounts.sign_in_state("kb") == :claimable
    end

    test "keeps email addresses unique across accounts" do
      user = user_fixture()
      configure_admins(["kb" | Accounts.admin_usernames()])

      assert {:error, changeset} =
               Accounts.claim_account("kb", %{password: "a long password", email: user.email},
                 invited: true
               )

      assert %{email: ["is already in use"]} = errors_on(changeset)
    end

    # The window this closes: a name stands in the configuration and its
    # owner has not signed in yet. Without the invitation, whoever
    # guesses the name first becomes an admin, and the bylines of the
    # blog publish the names.
    test "refuses an uninvited claim once the installation has an account" do
      user_fixture(%{username: "kb"})
      configure_admins(["kb", "anna"])

      attrs = %{password: "a long password", email: "anna@example.org"}
      assert {:error, :not_allowed} = Accounts.claim_account("anna", attrs)
      assert Accounts.sign_in_state("anna") == :claimable
    end

    test "an invited name claims its account" do
      user_fixture(%{username: "kb"})
      configure_admins(["kb", "anna"])

      attrs = %{password: "a long password", email: "anna@example.org"}
      assert {:ok, user} = Accounts.claim_account("anna", attrs, invited: true)
      assert user.username == "anna"
    end

    # A fresh installation has nobody who could invite, so the first
    # account is claimed without one.
    test "the first account of an empty installation needs no invitation" do
      configure_admins(["kb"])

      attrs = %{password: "a long password", email: "kb@example.org"}
      assert {:ok, _user} = Accounts.claim_account("kb", attrs)
    end

    test "mails a confirmation without the password when a site is given" do
      configure_admins(["kb"])
      attrs = %{password: "a long password", email: "kb@example.org"}

      assert {:ok, _user} = Accounts.claim_account("kb", attrs, site: "texttile.blog")

      assert_email_sent(fn email ->
        assert email.to == [{"kb", "kb@example.org"}]
        assert email.subject =~ "texttile.blog"
        refute email.text_body =~ "a long password"
        true
      end)
    end

    test "mails from the site title, not from the product name" do
      configure_admins(["kb"])
      {:ok, _} = Texttile.Settings.put(:site_title, "Breyer Blog")
      attrs = %{password: "a long password", email: "kb@example.org"}

      assert {:ok, _user} = Accounts.claim_account("kb", attrs, site: "texttile.blog")

      assert_email_sent(fn email ->
        assert {"Breyer Blog", _address} = email.from
        true
      end)
    end

    test "the displayed name may stay empty, the username stands in" do
      configure_admins(["kb"])

      assert {:ok, user} =
               Accounts.claim_account("kb", %{
                 password: "a long password",
                 email: "kb@example.org"
               })

      assert Accounts.display_name(user) == "kb"
    end

    test "refuses a name that nobody configured" do
      configure_admins(["kb"])

      assert {:error, :not_allowed} =
               Accounts.claim_account("julia", %{
                 password: "a long password",
                 email: "j@example.org"
               })

      assert Accounts.sign_in_state("julia") == :unknown
    end

    test "refuses a name that already has an account" do
      user_fixture(%{username: "kb"})

      assert {:error, :taken} =
               Accounts.claim_account("kb", %{
                 password: "another long password",
                 email: "x@example.org"
               })
    end

    test "keeps the password rules and its confirmation" do
      configure_admins(["kb"])

      assert {:error, changeset} =
               Accounts.claim_account("kb", %{
                 password: "short",
                 password_confirmation: "short",
                 email: "kb@example.org"
               })

      assert %{password: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Accounts.claim_account("kb", %{
                 password: "a long password",
                 password_confirmation: "a long passwort",
                 email: "kb@example.org"
               })

      assert %{password_confirmation: [_]} = errors_on(changeset)
    end

    test "normalizes the name" do
      configure_admins(["kb"])

      assert {:ok, user} =
               Accounts.claim_account(" KB ", %{
                 password: "a long password",
                 email: "kb@example.org"
               })

      assert user.username == "kb"
    end
  end

  describe "open_claim?/1" do
    test "is true for a configured name while the installation has no account" do
      configure_admins(["kb"])
      assert Accounts.open_claim?("kb")
    end

    test "is false once any account exists" do
      user_fixture(%{username: "kb"})
      configure_admins(["kb", "anna"])
      refute Accounts.open_claim?("anna")
    end

    test "is false for a name nobody configured" do
      configure_admins(["kb"])
      refute Accounts.open_claim?("stranger")
    end
  end

  describe "unclaimed_usernames/0" do
    test "names the configured people who have no account yet" do
      user_fixture(%{username: "kb"})
      configure_admins(["kb", "anna", "tom"])

      assert Accounts.unclaimed_usernames() == ["anna", "tom"]
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

      assert Enum.map(sessions, & &1.token_hash) ==
               Enum.map([t2, t1], &Accounts.session_fingerprint/1)
    end

    test "delete_all_sessions/1 ends every session, the current one included" do
      user = user_fixture()
      t1 = Accounts.create_session(user)
      t2 = Accounts.create_session(user)

      assert :ok = Accounts.delete_all_sessions(user)

      assert Accounts.list_sessions(user) == []
      assert Accounts.get_user_by_session_token(t1) == nil
      assert Accounts.get_user_by_session_token(t2) == nil
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
      kept = Accounts.session_fingerprint(keep)
      assert [%{token_hash: ^kept}] = Accounts.list_sessions(user)
    end

    test "an expired token no longer signs anybody in and drops out of the list" do
      user = user_fixture()
      token = Accounts.create_session(user)

      three_days_on = DateTime.add(DateTime.utc_now(), 3 * 86_400, :second)

      assert Accounts.get_user_by_session_token(token, now: three_days_on) == nil
      assert Accounts.list_sessions(user, now: three_days_on) == []
    end

    test "a session lasts two days, and fourteen when the browser is remembered" do
      user = user_fixture()
      now = DateTime.utc_now()

      short = Accounts.create_session(user)
      long = Accounts.create_session(user, remember: true)

      assert_in_delta days_from(now, expiry_of(short)), 2, 0.01
      assert_in_delta days_from(now, expiry_of(long)), 14, 0.01
    end

    test "session_max_age/1 says the same in seconds" do
      assert Accounts.session_max_age(false) == 2 * 24 * 60 * 60
      assert Accounts.session_max_age(true) == 14 * 24 * 60 * 60
    end

    test "opening a session sweeps the sessions whose day has passed" do
      user = user_fixture()
      stale = Accounts.create_session(user)

      past_every_expiry = DateTime.add(DateTime.utc_now(), 15 * 86_400, :second)
      _fresh = Accounts.create_session(user, now: past_every_expiry)

      refute Texttile.Repo.get_by(Texttile.Accounts.Session,
               token_hash: Accounts.session_fingerprint(stale)
             )
    end

    # SQLite keeps a moment as text and every comparison here is a
    # comparison of strings, so the shape has to be the adapter's own.
    # The migration that gave the open sessions their day writes it by
    # hand; this is that shape, read back.
    test "a row whose expiry was written as text is read the same way" do
      user = user_fixture()
      token = Accounts.create_session(user)

      Texttile.Repo.query!(
        "UPDATE sessions SET expires_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+14 days')"
      )

      assert Accounts.get_user_by_session_token(token).id == user.id
      assert [%{}] = Accounts.list_sessions(user)
      assert days_from(DateTime.utc_now(), expiry_of(token)) > 13.9
    end

    defp expiry_of(token) do
      Texttile.Repo.get_by!(Texttile.Accounts.Session,
        token_hash: Accounts.session_fingerprint(token)
      ).expires_at
    end

    defp days_from(now, expires_at), do: DateTime.diff(expires_at, now) / 86_400
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
