defmodule Texttile.AccountsTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  defp link_url(token), do: "http://localhost/link/#{token}"

  defp invite_opts, do: [site: "texttile.blog", link_url: &link_url/1]

  # The token out of the next mail this test has waiting.
  defp mailed_token do
    assert_received {:email, email}
    [_, token] = Regex.run(~r{/link/(\S+)}, email.text_body)
    token
  end

  describe "invite/2" do
    test "makes the account and mails it the link that sets its password" do
      assert {:ok, user} = Accounts.invite("Anna@Example.ORG", invite_opts())

      assert user.email == "anna@example.org"
      assert Accounts.pending?(user)
      assert :error = Accounts.authenticate_user("anna@example.org", valid_password())

      assert_email_sent(fn email ->
        assert email.to == [{"anna", "anna@example.org"}]
        assert email.subject =~ "texttile.blog"
        assert email.text_body =~ "http://localhost/link/"
        true
      end)
    end

    test "the mailed link gives the account its password" do
      {:ok, user} = Accounts.invite("anna@example.org", invite_opts())
      token = mailed_token()

      assert {:ok, user} = Accounts.accept_login_link(token, "a long enough password")
      refute Accounts.pending?(user)

      assert {:ok, found} =
               Accounts.authenticate_user("anna@example.org", "a long enough password")

      assert found.id == user.id
    end

    test "an address that is still waiting gets a fresh link, not a second account" do
      {:ok, first} = Accounts.invite("anna@example.org", invite_opts())
      assert {:ok, again} = Accounts.invite("anna@example.org", invite_opts())

      assert again.id == first.id
      assert length(Accounts.list_users()) == 1
    end

    test "an address whose account has a password is refused" do
      user = user_fixture()
      assert {:error, :exists} = Accounts.invite(user.email, invite_opts())
    end

    test "refuses something that is not an address" do
      assert {:error, changeset} = Accounts.invite("anna", invite_opts())
      assert %{email: [_]} = errors_on(changeset)
      assert Accounts.list_users() == []
    end

    # The account is the half that is worth keeping: the link can go out
    # again, and a second attempt would otherwise make a second account.
    test "a mail that cannot leave says so and leaves the account standing" do
      break_mail()

      assert {:error, {:mail, _reason}} = Accounts.invite("anna@example.org", invite_opts())
      assert [%{email: "anna@example.org"}] = Accounts.list_users()
    end
  end

  describe "invite_configured/1" do
    test "invites the configured address that has no account" do
      configure_admin_emails(["kb@example.org"])

      Accounts.invite_configured(invite_opts())

      assert [%{email: "kb@example.org"} = user] = Accounts.list_users()
      assert Accounts.pending?(user)
      assert_email_sent(fn email -> assert email.to == [{"kb", "kb@example.org"}] end)
    end

    test "leaves an account that can sign in alone" do
      user = user_fixture(%{email: "kb@example.org"})
      configure_admin_emails(["kb@example.org"])

      Accounts.invite_configured(invite_opts())

      assert [%{id: id}] = Accounts.list_users()
      assert id == user.id
      assert_no_email_sent()
    end

    # The restart is the way back into an installation whose first mail
    # never arrived, so it mints the link again.
    test "mints the link again while nobody can sign in" do
      configure_admin_emails(["kb@example.org"])
      Accounts.invite_configured(invite_opts())
      first = mailed_token()

      minute_on = DateTime.add(DateTime.utc_now(), 120, :second)
      Accounts.invite_configured(invite_opts() ++ [now: minute_on])

      assert :error = Accounts.verify_login_link(first)
      assert {:ok, _} = Accounts.verify_login_link(mailed_token())
    end

    # A crash loop restarts in seconds, and every restart would
    # otherwise mail again and kill the link that is on its way.
    test "mails nothing twice within a minute" do
      configure_admin_emails(["kb@example.org"])
      Accounts.invite_configured(invite_opts())
      token = mailed_token()

      Accounts.invite_configured(invite_opts())

      assert_no_email_sent()
      assert {:ok, _} = Accounts.verify_login_link(token)
    end

    # Somebody is in, so the waiting account is theirs to chase, not the
    # server's: a restart must not mail a person again and again.
    test "leaves a waiting account alone once somebody can sign in" do
      user_fixture()
      invited_user_fixture("anna@example.org")
      configure_admin_emails(["anna@example.org"])

      Accounts.invite_configured(invite_opts())

      assert_no_email_sent()
    end

    # Deleting the account is the whole revocation model now, so a
    # restart must not hand the address back. The variable adds each
    # address once and remembers it.
    test "a deleted account does not come back at the next start" do
      configure_admin_emails(["kb@example.org"])
      Accounts.invite_configured(invite_opts())
      [invited] = Accounts.list_users()

      me = user_fixture()
      {:ok, _} = Accounts.delete_user(invited, by: me)

      Accounts.invite_configured(invite_opts())

      assert Accounts.get_user_by_email("kb@example.org") == nil
      assert Enum.map(Accounts.list_users(), & &1.id) == [me.id]
    end

    # The address the account left is an address this installation has
    # made once. A second account for it would belong to whoever reads
    # an inbox its owner walked away from.
    test "an address the account moved away from makes no second account" do
      configure_admin_emails(["kb@example.org"])
      Accounts.invite_configured(invite_opts())
      token = mailed_token()
      {:ok, user} = Accounts.accept_login_link(token, "a long enough password")
      {:ok, _} = Accounts.update_email(user, "kb@elsewhere.org", "a long enough password")

      Accounts.invite_configured(invite_opts())

      assert Accounts.get_user_by_email("kb@example.org") == nil
      assert length(Accounts.list_users()) == 1
    end

    # The memory is about the installation, not about the variable: an
    # address Settings made and somebody deleted stays deleted too.
    test "an address an admin invited and deleted is not made again" do
      me = user_fixture()
      {:ok, anna} = Accounts.invite("anna@example.org", invite_opts())
      {:ok, _} = Accounts.delete_user(anna, by: me)

      configure_admin_emails(["anna@example.org"])
      Accounts.invite_configured(invite_opts())

      assert Accounts.get_user_by_email("anna@example.org") == nil
    end

    # The variable is still a way to add somebody without touching
    # Settings: an address it never made before gets its account.
    test "an address added to the configuration later gets its account" do
      user_fixture()
      configure_admin_emails(["kb@example.org"])

      Accounts.invite_configured(invite_opts())

      assert Accounts.pending?(Accounts.get_user_by_email("kb@example.org"))
    end

    # Nobody is at the screen when this runs, so a mail that stays here
    # has to say so in the log.
    test "a mail that cannot leave at the start says so in the log" do
      break_mail()
      configure_admin_emails(["kb@example.org"])

      log = ExUnit.CaptureLog.capture_log(fn -> Accounts.invite_configured(invite_opts()) end)

      assert log =~ "kb@example.org"
      assert log =~ "did not leave this server"
      assert Accounts.get_user_by_email("kb@example.org")
    end

    test "an address that is not one is dropped by the configuration, not by this" do
      configure_admin_emails([])
      Accounts.invite_configured(invite_opts())
      assert Accounts.list_users() == []
    end
  end

  describe "nobody_can_sign_in?/0" do
    test "true for an empty installation and for one that is only invited" do
      assert Accounts.nobody_can_sign_in?()

      invited_user_fixture("anna@example.org")
      assert Accounts.nobody_can_sign_in?()

      user_fixture()
      refute Accounts.nobody_can_sign_in?()
    end

    # The way into an installation whose mail does not leave. It closes
    # itself: the first password ends it.
    test "the link stands in the log while nobody can sign in" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, _} = Accounts.invite("anna@example.org", invite_opts())
        end)

      assert log =~ "http://localhost/link/"
      assert log =~ "anna@example.org"
    end

    test "no link stands in the log once somebody can sign in" do
      user = user_fixture()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, _} = Accounts.send_password_link(user, invite_opts())
        end)

      refute log =~ "http://localhost/link/"
    end
  end

  describe "authenticate_user/2" do
    test "returns the user for the right address and password" do
      user = user_fixture()
      assert {:ok, found} = Accounts.authenticate_user(user.email, valid_password())
      assert found.id == user.id
    end

    test "accepts the address in any case, with spaces around it" do
      user = user_fixture(%{email: "kb@example.org"})
      assert {:ok, found} = Accounts.authenticate_user(" KB@Example.ORG ", valid_password())
      assert found.id == user.id
    end

    test "rejects a wrong password" do
      user = user_fixture()
      assert :error = Accounts.authenticate_user(user.email, "wrong password!")
    end

    test "rejects an address without an account" do
      assert :error = Accounts.authenticate_user("nobody@example.org", valid_password())
    end

    # The account exists and its address is no secret. Until the link
    # gives it a password, no password opens it.
    test "rejects an account that is still waiting for its first password" do
      user = invited_user_fixture("anna@example.org")
      assert Accounts.pending?(user)
      assert :error = Accounts.authenticate_user("anna@example.org", valid_password())
      assert :error = Accounts.authenticate_user("anna@example.org", "")
    end

    # ADMIN_USERS is not the guest list any more: it only ever adds.
    test "an account stays valid when its address leaves the configuration" do
      user = user_fixture()
      configure_admin_emails([])
      assert {:ok, _} = Accounts.authenticate_user(user.email, valid_password())
    end
  end

  describe "sessions" do
    test "create_session/1 returns a token that finds the user" do
      user = user_fixture()
      token = Accounts.create_session(user)
      assert Accounts.get_user_by_session_token(token).id == user.id
    end

    # SQLite keeps the storage class of what was written, and it never
    # reads a text value as equal to a blob parameter. The migration
    # that hashed the open sessions writes this row by hand, so this is
    # that row, read back the way a request reads it. Written any other
    # way it is a row nobody can ever find again, and every browser that
    # was signed in at the upgrade would be signed out by it.
    test "a session row written the way the migration writes it still signs its browser in" do
      user = user_fixture()
      token = :crypto.strong_rand_bytes(32)
      hash = Accounts.session_fingerprint(token)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      expires_at = DateTime.add(now, 2 * 24 * 60 * 60, :second)

      Texttile.Repo.query!(
        "INSERT INTO sessions (token_hash, user_id, expires_at, inserted_at) VALUES (?1, ?2, ?3, ?4)",
        [{:blob, hash}, user.id, expires_at, now]
      )

      assert Accounts.get_user_by_session_token(token).id == user.id
      assert :ok = Accounts.delete_session(token)
      assert Accounts.list_sessions(user) == []
    end

    # The other half of the rule above, so the reason it is written that
    # way cannot be refactored away by accident: the same bytes stored
    # as text are a row nobody can reach.
    test "the same hash stored as text finds nobody" do
      user = user_fixture()
      token = :crypto.strong_rand_bytes(32)
      hash = Accounts.session_fingerprint(token)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      expires_at = DateTime.add(now, 2 * 24 * 60 * 60, :second)

      Texttile.Repo.query!(
        "INSERT INTO sessions (token_hash, user_id, expires_at, inserted_at) VALUES (?1, ?2, ?3, ?4)",
        [hash, user.id, expires_at, now]
      )

      refute Accounts.get_user_by_session_token(token)
    end

    test "get_user_by_session_token/1 returns nil for an unknown token" do
      assert Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32)) == nil
    end

    # Deleting the account is what ends the browsers it left open, and
    # the rows go with it.
    test "get_user_by_session_token/1 finds nobody once the account is gone" do
      me = user_fixture()
      other = user_fixture()
      token = Accounts.create_session(other)
      assert Accounts.get_user_by_session_token(token).id == other.id

      {:ok, _} = Accounts.delete_user(other, by: me)
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
    test "update_display_name/2 accepts any text, including nothing" do
      user = user_fixture(%{email: "kb@example.org"})
      assert {:ok, user} = Accounts.update_display_name(user, "Klaus")
      assert user.display_name == "Klaus"
      assert {:ok, user} = Accounts.update_display_name(user, "")
      assert Accounts.display_name(user) == "kb"
    end

    # The address is the identity, and it is not for readers. What a
    # blank name falls back to is the part in front of the @, never the
    # address itself.
    test "display_name/1 falls back to the part before the @" do
      user = user_fixture(%{email: "kb@example.org"})
      assert Accounts.display_name(user) == "kb"
      {:ok, user} = Accounts.update_display_name(user, "   ")
      assert Accounts.display_name(user) == "kb"
      refute Accounts.display_name(user) =~ "@"
      {:ok, user} = Accounts.update_display_name(user, "Klaus")
      assert Accounts.display_name(user) == "Klaus"
    end

    test "update_email/3 changes and normalizes the address" do
      user = user_fixture()
      assert {:ok, user} = Accounts.update_email(user, "New@Example.ORG", valid_password())
      assert user.email == "new@example.org"
      assert {:ok, _} = Accounts.authenticate_user("new@example.org", valid_password())
    end

    # Whoever holds the address holds the account: the next password
    # link goes there. A stolen session must not be enough to move it.
    test "update_email/3 needs the current password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_email(user, "new@example.org", "wrong current!")

      assert %{current_password: [_]} = errors_on(changeset)
      assert Accounts.get_user!(user.id).email == user.email
    end

    test "update_email/3 keeps addresses unique" do
      user_fixture(%{email: "taken@example.org"})
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_email(user, "Taken@example.org", valid_password())

      assert %{email: [_]} = errors_on(changeset)
    end

    # A link that is on its way to the old inbox dies with the move,
    # because links belong to the account and not to the address.
    test "update_email/3 spends the link that was mailed to the old address" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, invite_opts())

      {:ok, _} = Accounts.update_email(user, "moved@example.org", valid_password())

      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "a long enough password")
    end

    test "update_email/3 rejects an invalid address" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.update_email(user, "not-a-mail", valid_password())
      assert %{email: [_]} = errors_on(changeset)
    end

    test "update_password/3 needs the current password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_password(user, "wrong current!", "a brand new password")

      assert %{current_password: [_]} = errors_on(changeset)

      assert {:ok, user} =
               Accounts.update_password(user, valid_password(), "a brand new password")

      assert {:ok, _} = Accounts.authenticate_user(user.email, "a brand new password")
      assert :error = Accounts.authenticate_user(user.email, valid_password())
    end

    # The reset somebody asked for and never used opens nothing once
    # the owner has set the password themselves.
    test "update_password/3 spends the link that is still in flight" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, invite_opts())

      {:ok, _} = Accounts.update_password(user, valid_password(), "a brand new password")

      assert :error = Accounts.verify_login_link(token)
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
      assert {:ok, _} = Accounts.authenticate_user(stale.email, "third password!!")
    end
  end

  describe "delete_user/2" do
    test "deletes another account with its sessions" do
      me = user_fixture(%{display_name: "kb"})
      other = user_fixture(%{display_name: "julia"})
      Accounts.create_session(other)

      assert {:ok, _} = Accounts.delete_user(other, by: me)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(other.id) end
      assert Accounts.list_sessions(other) == []
    end

    test "never you, never the last account" do
      me = user_fixture(%{display_name: "kb"})
      assert {:error, :last} = Accounts.delete_user(me, by: me)

      other = user_fixture(%{display_name: "julia"})
      assert {:error, :yourself} = Accounts.delete_user(other, by: other)
    end

    test "an account another admin deleted first answers :gone, not a crash" do
      me = user_fixture(%{display_name: "kb"})
      other = user_fixture(%{display_name: "julia"})
      _third = user_fixture(%{display_name: "pat"})

      {:ok, _} = Accounts.delete_user(other, by: me)
      assert {:error, :gone} = Accounts.delete_user(other, by: me)
    end
  end

  describe "list_users/0" do
    test "everybody, oldest account first" do
      kb = user_fixture(%{display_name: "kb"})
      julia = user_fixture(%{display_name: "julia"})

      assert Enum.map(Accounts.list_users(), & &1.id) == [kb.id, julia.id]
    end
  end
end
