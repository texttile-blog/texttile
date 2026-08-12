defmodule Texttile.AccountsLinksTest do
  @moduledoc """
  The mailed link that sets a new password: the one way back into an
  account whose password is gone. Nothing here invites anybody; the
  configuration does that.
  """
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  defp link_url(token), do: "http://localhost/link/#{token}"

  describe "password links" do
    test "the mailed token sets the password once and then is spent" do
      user = user_fixture(%{username: "julia"})
      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      assert {:ok, verified} = Accounts.verify_login_link(token)
      assert verified.id == user.id

      assert {:ok, _user} = Accounts.accept_login_link(token, "a long enough password")
      assert {:ok, _} = Accounts.authenticate_user("julia", "a long enough password")

      # one use: the same link answers nothing afterwards
      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "another long password")
    end

    test "a link older than a day answers nothing" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      next_day = DateTime.add(DateTime.utc_now(), 25 * 3600, :second)

      assert :error = Accounts.verify_login_link(token, now: next_day)
      assert :error = Accounts.accept_login_link(token, "a long enough password", now: next_day)
    end

    test "a fresh link replaces the earlier one" do
      user = user_fixture()
      {:ok, old} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)
      {:ok, new} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      assert :error = Accounts.verify_login_link(old)
      assert {:ok, _} = Accounts.verify_login_link(new)
    end

    test "a reset for a signed-up account mails reset wording and ends the sessions" do
      user = user_fixture(%{username: "kb"})
      _token = Accounts.create_session(user)

      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)
      assert_email_sent(fn email -> assert email.subject =~ "password" end)

      assert {:ok, _} = Accounts.accept_login_link(token, "a brand new password")
      assert Accounts.list_sessions(user) == []
      assert :error = Accounts.authenticate_user("kb", valid_password())
      assert {:ok, _} = Accounts.authenticate_user("kb", "a brand new password")
    end

    test "a rejected password leaves the link usable" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      assert {:error, changeset} = Accounts.accept_login_link(token, "short")
      assert "use at least 12 characters" in errors_on(changeset).password
      assert {:ok, _} = Accounts.verify_login_link(token)
    end
  end

  describe "link_recently_sent?/1" do
    test "true just after a link went out, false for an old one" do
      user = user_fixture()
      refute Accounts.link_recently_sent?(user)

      {:ok, _} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)
      assert Accounts.link_recently_sent?(user)

      two_minutes_on = DateTime.add(DateTime.utc_now(), 120, :second)
      refute Accounts.link_recently_sent?(user, now: two_minutes_on)
    end
  end

  describe "the configuration guards the link" do
    test "no link goes to an address whose name left the list" do
      user = user_fixture(%{username: "julia"})
      assert Accounts.get_user_by_email(user.email).id == user.id

      configure_admins([])
      assert Accounts.get_user_by_email(user.email) == nil
    end

    test "a link in flight opens nothing once the name is gone" do
      user = user_fixture(%{username: "julia"})
      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      configure_admins([])

      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "a long enough password")
    end
  end
end
