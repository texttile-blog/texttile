defmodule Texttile.AccountsLinksTest do
  @moduledoc """
  The mailed link that sets a password: the invitation of a new admin
  and the way back into an account whose password is gone are the same
  link, and the mail says which of the two it is.
  """
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  defp link_url(token), do: "http://localhost/link/#{token}"

  defp link_opts, do: [site: "s", link_url: &link_url/1]

  describe "password links" do
    test "the mailed token sets the password once and then is spent" do
      user = user_fixture(%{email: "julia@example.org"})
      {:ok, token} = Accounts.send_password_link(user, link_opts())

      assert {:ok, verified} = Accounts.verify_login_link(token)
      assert verified.id == user.id

      assert {:ok, _user} = Accounts.accept_login_link(token, "a long enough password")

      assert {:ok, _} =
               Accounts.authenticate_user("julia@example.org", "a long enough password")

      # one use: the same link answers nothing afterwards
      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "another long password")
    end

    test "a reset link older than a day answers nothing" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, link_opts())

      next_day = DateTime.add(DateTime.utc_now(), 25 * 3600, :second)

      assert :error = Accounts.verify_login_link(token, now: next_day)
      assert :error = Accounts.accept_login_link(token, "a long enough password", now: next_day)
    end

    # An invitation travels to somebody who is not waiting for it, so a
    # day is short: it holds a week.
    test "an invitation holds a week, and not a day longer" do
      user = invited_user_fixture("anna@example.org")
      {:ok, token} = Accounts.send_password_link(user, link_opts())

      next_day = DateTime.add(DateTime.utc_now(), 25 * 3600, :second)
      next_week = DateTime.add(DateTime.utc_now(), 8 * 24 * 3600, :second)

      assert {:ok, _} = Accounts.verify_login_link(token, now: next_day)
      assert :error = Accounts.verify_login_link(token, now: next_week)
    end

    # The week belongs to the account that never had a password, not to
    # the link: once it has one, its next link is a reset.
    test "the account that used its invitation gets a day from then on" do
      user = invited_user_fixture("anna@example.org")
      {:ok, token} = Accounts.send_password_link(user, link_opts())
      {:ok, user} = Accounts.accept_login_link(token, "a long enough password")

      {:ok, reset} = Accounts.send_password_link(user, link_opts())
      next_day = DateTime.add(DateTime.utc_now(), 25 * 3600, :second)

      assert :error = Accounts.verify_login_link(reset, now: next_day)
    end

    test "a fresh link replaces the earlier one" do
      user = user_fixture()
      {:ok, old} = Accounts.send_password_link(user, link_opts())
      {:ok, new} = Accounts.send_password_link(user, link_opts())

      assert :error = Accounts.verify_login_link(old)
      assert {:ok, _} = Accounts.verify_login_link(new)
    end

    test "a reset for a signed-up account mails reset wording and ends the sessions" do
      user = user_fixture(%{email: "kb@example.org"})
      _token = Accounts.create_session(user)

      {:ok, token} = Accounts.send_password_link(user, link_opts())
      assert_email_sent(fn email -> assert email.subject =~ "password" end)

      assert {:ok, _} = Accounts.accept_login_link(token, "a brand new password")
      assert Accounts.list_sessions(user) == []
      assert :error = Accounts.authenticate_user("kb@example.org", valid_password())
      assert {:ok, _} = Accounts.authenticate_user("kb@example.org", "a brand new password")
    end

    # The account that never had a password is being invited, not reset,
    # and the mail says so.
    test "an account without a password reads an invitation" do
      user = invited_user_fixture("anna@example.org")

      {:ok, _token} = Accounts.send_password_link(user, link_opts())

      assert_email_sent(fn email ->
        assert email.subject =~ "admin account"
        assert email.text_body =~ "for a week"
        true
      end)
    end

    test "a rejected password leaves the link usable" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, link_opts())

      assert {:error, changeset} = Accounts.accept_login_link(token, "short")
      assert "use at least 12 characters" in errors_on(changeset).password
      assert {:ok, _} = Accounts.verify_login_link(token)
    end
  end

  describe "link_recently_sent?/1" do
    test "true just after a link went out, false for an old one" do
      user = user_fixture()
      refute Accounts.link_recently_sent?(user)

      {:ok, _} = Accounts.send_password_link(user, link_opts())
      assert Accounts.link_recently_sent?(user)

      two_minutes_on = DateTime.add(DateTime.utc_now(), 120, :second)
      refute Accounts.link_recently_sent?(user, now: two_minutes_on)
    end
  end

  describe "the account is what the link belongs to" do
    # ADMIN_USERS took access away once. It does not any more: the
    # accounts are the guest list, and deleting one is what ends it.
    test "a deleted account owns no link any more" do
      me = user_fixture()
      other = user_fixture(%{email: "julia@example.org"})
      {:ok, token} = Accounts.send_password_link(other, link_opts())

      {:ok, _} = Accounts.delete_user(other, by: me)

      assert Accounts.get_user_by_email("julia@example.org") == nil
      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "a long enough password")
    end

    test "an address out of the configuration keeps its account and its link" do
      user = user_fixture(%{email: "julia@example.org"})
      configure_admin_emails([])
      {:ok, token} = Accounts.send_password_link(user, link_opts())

      assert Accounts.get_user_by_email("julia@example.org").id == user.id
      assert {:ok, _} = Accounts.verify_login_link(token)
    end
  end
end
