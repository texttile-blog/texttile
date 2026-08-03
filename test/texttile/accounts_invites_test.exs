defmodule Texttile.AccountsInvitesTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  defp link_url(token), do: "http://localhost/link/#{token}"

  describe "create_user/2" do
    test "creates an invited account without a password and mails the link" do
      {:ok, user} =
        Accounts.create_user(%{"username" => "Julia", "email" => "julia@example.org"},
          site: "texttile.blog",
          link_url: &link_url/1
        )

      assert user.username == "julia"
      assert user.password_hash == nil
      assert Accounts.invited?(user)

      assert_email_sent(fn email ->
        assert email.subject =~ "texttile.blog"
        assert [{_, "julia@example.org"}] = email.to
        assert email.text_body =~ "http://localhost/link/"
      end)
    end

    test "refuses a taken username" do
      user_fixture(%{username: "kb"})

      assert {:error, changeset} =
               Accounts.create_user(%{"username" => "kb", "email" => "kb2@example.org"},
                 site: "s",
                 link_url: &link_url/1
               )

      assert "is already taken" in errors_on(changeset).username
    end

    test "an invited account cannot sign in yet" do
      {:ok, _} =
        Accounts.create_user(%{"username" => "julia", "email" => "julia@example.org"},
          site: "s",
          link_url: &link_url/1
        )

      assert :error = Accounts.authenticate_user("julia", "anything at all")
    end
  end

  describe "password links" do
    test "the mailed token sets the password once and then is spent" do
      {:ok, user} =
        Accounts.create_user(%{"username" => "julia", "email" => "julia@example.org"},
          site: "s",
          link_url: fn token -> send(self(), {:token, token}) && link_url(token) end
        )

      assert_receive {:token, token}
      assert {:ok, verified} = Accounts.verify_login_link(token)
      assert verified.id == user.id

      assert {:ok, _user} = Accounts.accept_login_link(token, "a long enough password")
      assert {:ok, _} = Accounts.authenticate_user("julia", "a long enough password")
      refute Accounts.invited?(Accounts.get_user!(user.id))

      # one use: the same link answers nothing afterwards
      assert :error = Accounts.verify_login_link(token)
      assert :error = Accounts.accept_login_link(token, "another long password")
    end

    test "a link older than a day answers nothing" do
      user = user_fixture()
      {:ok, token} = Accounts.send_password_link(user, site: "s", link_url: &link_url/1)

      Repo.update_all("login_links", set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

      assert :error = Accounts.verify_login_link(token)
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
      assert {:error, :yourself} = Accounts.delete_user(me, by: me)

      other = user_fixture(%{username: "julia"})
      assert {:error, :yourself} = Accounts.delete_user(other, by: other)
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
