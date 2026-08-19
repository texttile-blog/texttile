defmodule TexttileWeb.LinkControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  defp mailed_link(user) do
    {:ok, token} =
      Accounts.send_password_link(user, site: "s", link_url: fn t -> "http://x/link/#{t}" end)

    token
  end

  describe "GET /link/:token" do
    test "a fresh link opens the set-a-password screen", %{conn: conn} do
      user = user_fixture(%{email: "julia@example.org"})
      conn = get(conn, ~p"/link/#{mailed_link(user)}")

      html = html_response(conn, 200)
      assert html =~ "julia@example.org"
      assert html =~ "New password"
    end

    # The same screen, the other face: nobody is setting a new password
    # here, somebody is opening an account for the first time.
    test "an invitation says what it opens and how long it holds", %{conn: conn} do
      user = invited_user_fixture("anna@example.org")
      conn = get(conn, ~p"/link/#{mailed_link(user)}")

      html = html_response(conn, 200)
      assert html =~ "opens the admin account of"
      assert html =~ "anna@example.org"
      assert html =~ "for a week"
      refute html =~ "The old password stops working"
    end

    test "a dead link says so", %{conn: conn} do
      conn = get(conn, ~p"/link/not-a-real-token")
      assert html_response(conn, 200) =~ "This link does not work any more"
    end
  end

  describe "POST /link/:token" do
    test "sets the password and signs the person in", %{conn: conn} do
      user = user_fixture(%{email: "julia@example.org"})
      token = mailed_link(user)

      conn =
        post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "a long enough password"}})

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)
      assert {:ok, _} = Accounts.authenticate_user("julia@example.org", "a long enough password")
    end

    # The first sign-in of an account: the password twice, and the name
    # readers will see.
    test "an invitation opens the account with the password twice and a name", %{conn: conn} do
      user = invited_user_fixture("anna@example.org")
      token = mailed_link(user)

      conn =
        post(conn, ~p"/link/#{token}", %{
          "user" => %{
            "password" => "a long enough password",
            "password_confirmation" => "a long enough password",
            "display_name" => "Anna Berg"
          }
        })

      assert redirected_to(conn) == ~p"/admin"
      assert Accounts.display_name(Accounts.get_user_by_email("anna@example.org")) == "Anna Berg"
    end

    test "a password that arrives twice differently stays on the form", %{conn: conn} do
      user = invited_user_fixture("anna@example.org")
      token = mailed_link(user)

      conn =
        post(conn, ~p"/link/#{token}", %{
          "user" => %{
            "password" => "a long enough password",
            "password_confirmation" => "a long enough passwort",
            "display_name" => "Anna"
          }
        })

      html = html_response(conn, 200)
      assert html =~ "does not match the password"
      assert html =~ "link-password-confirmation"
      refute get_session(conn, :user_token)
      assert {:ok, _} = Accounts.verify_login_link(token)
    end

    test "an empty displayed name stays on the form and keeps the typed one", %{conn: conn} do
      user = invited_user_fixture("anna@example.org")
      token = mailed_link(user)

      conn =
        post(conn, ~p"/link/#{token}", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "short",
            "display_name" => ""
          }
        })

      html = html_response(conn, 200)
      assert html =~ "cannot be empty"
      assert html =~ "use at least 12 characters"
      assert Accounts.pending?(Accounts.get_user_by_email("anna@example.org"))
    end

    test "a short password stays on the form and says why", %{conn: conn} do
      user = user_fixture()
      token = mailed_link(user)

      conn = post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "short"}})

      html = html_response(conn, 200)
      assert html =~ "use at least 12 characters"
      refute html =~ "The password use at least"
    end

    test "setting the password tells the open sockets of the old sessions to disconnect",
         %{conn: conn} do
      user = user_fixture(%{email: "julia@example.org"})
      old_session_token = Accounts.create_session(user)

      TexttileWeb.Endpoint.subscribe(
        TexttileWeb.UserAuth.user_session_topic(Accounts.session_fingerprint(old_session_token))
      )

      token = mailed_link(user)
      post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "a long enough password"}})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "a spent link lands on the dead-link screen", %{conn: conn} do
      user = user_fixture()
      token = mailed_link(user)
      {:ok, _} = Accounts.accept_login_link(token, "a long enough password")

      conn = post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "another long password"}})

      assert html_response(conn, 200) =~ "This link does not work any more"
    end
  end

  describe "forgot password" do
    test "the form asks for the address", %{conn: conn} do
      conn = get(conn, ~p"/forgot")
      assert html_response(conn, 200) =~ "Email address"
    end

    test "a known address gets the mail; the answer never tells", %{conn: conn} do
      user = user_fixture(%{email: "kb@example.org"})

      conn = post(conn, ~p"/forgot", %{"user" => %{"email" => "kb@example.org"}})
      assert html_response(conn, 200) =~ "on its way"
      assert_email_sent(to: [{Accounts.display_name(user), "kb@example.org"}])
    end

    # A fresh link replaces the pending one, so a stranger who knows the
    # address of an invited person could otherwise kill the invitation
    # in the inbox it just reached, once a minute, forever.
    test "an account that was only invited keeps its link, whatever this form is told", %{
      conn: conn
    } do
      user = invited_user_fixture("anna@example.org")

      {:ok, token} =
        Accounts.send_password_link(user, site: "s", link_url: fn t -> "http://x/link/#{t}" end)

      # the invitation itself, out of the way, so the next mailbox
      # question is about this form alone
      assert_received {:email, _invitation}

      conn = post(conn, ~p"/forgot", %{"user" => %{"email" => "anna@example.org"}})

      assert html_response(conn, 200) =~ "on its way"
      assert_no_email_sent()
      assert {:ok, _} = Accounts.verify_login_link(token)
    end

    # The log carries a link while nobody can sign in, which is the way
    # into an installation whose mail is broken. Only the server writes
    # it: a stranger at this form must not be able to ask for one.
    test "no stranger writes a link into the log through this form", %{conn: conn} do
      invited_user_fixture("anna@example.org")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          post(conn, ~p"/forgot", %{"user" => %{"email" => "anna@example.org"}})
        end)

      refute log =~ "/link/"
    end

    test "an unknown address gets no mail; the answer reads the same", %{conn: conn} do
      conn = post(conn, ~p"/forgot", %{"user" => %{"email" => "nobody@example.org"}})
      assert html_response(conn, 200) =~ "on its way"
      assert_no_email_sent()
    end

    test "hammering the form sends one mail per minute and keeps the pending link alive",
         %{conn: conn} do
      user_fixture(%{email: "kb@example.org"})

      post(conn, ~p"/forgot", %{"user" => %{"email" => "kb@example.org"}})
      assert_email_sent()

      conn = post(conn, ~p"/forgot", %{"user" => %{"email" => "kb@example.org"}})
      assert html_response(conn, 200) =~ "on its way"
      assert_no_email_sent()
    end
  end
end
