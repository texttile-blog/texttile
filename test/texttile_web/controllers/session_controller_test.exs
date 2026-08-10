defmodule TexttileWeb.SessionControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Accounts

  describe "GET /login" do
    test "shows the sign-in form once an account exists", %{conn: conn} do
      user_fixture()
      conn = get(conn, ~p"/login")
      response = html_response(conn, 200)
      assert response =~ "login-form"
      assert response =~ "Admin sign-in"
    end

    test "shows the same form on a fresh install", %{conn: conn} do
      # A name of two letters also hides inside the page's own CSRF
      # token now and then, and the refute below would read that as a
      # leak. The name only has to be one no configured admin shares
      # with a random string.
      configure_admins(["margarethe"])
      response = conn |> get(~p"/login") |> html_response(200)
      assert response =~ "login-form"
      refute response =~ "margarethe"
    end

    test "sends a signed-in admin to the admin area", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/login")
      assert redirected_to(conn) == ~p"/admin"
    end
  end

  describe "POST /login with a name that has no account yet" do
    setup do
      configure_admins(["kb"])
      :ok
    end

    test "offers the password screen", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"username" => "kb", "password" => ""}})

      response = html_response(conn, 200)
      assert response =~ "claim-form"
      assert response =~ "Choose a password"
      assert response =~ "kb"
      refute get_session(conn, :user_token)
    end

    test "offers the way back to the form for a mistyped name", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"username" => "kb", "password" => ""}})
      assert html_response(conn, 200) =~ "Sign in with another name"
    end

    test "does not ask for a password nobody has yet", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"username" => "kb", "password" => ""}})
      refute html_response(conn, 200) =~ "Both fields are required"
    end

    test "takes the name in any case", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"user" => %{"username" => " KB ", "password" => ""}})
      assert html_response(conn, 200) =~ "claim-form"
    end

    test "says nothing about a name that is not configured", %{conn: conn} do
      conn =
        post(conn, ~p"/login", %{"user" => %{"username" => "julia", "password" => "guess it"}})

      response = html_response(conn, 200)
      assert response =~ "do not match"
      refute response =~ "claim-form"
    end
  end

  describe "POST /login/claim" do
    setup do
      configure_admins(["kb"])
      :ok
    end

    test "creates the account and signs in", %{conn: conn} do
      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "kb",
            "password" => "a long password",
            "password_confirmation" => "a long password",
            "email" => "kb@example.org",
            "display_name" => "KB"
          }
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)
      assert Accounts.sign_in_state("kb") == :known

      assert %{email: "kb@example.org", display_name: "KB"} =
               Accounts.get_user_by_email("kb@example.org")

      conn = get(conn, ~p"/admin/texts")
      assert html_response(conn, 200) =~ "Entries"
    end

    test "keeps the screen when the two passwords differ", %{conn: conn} do
      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "kb",
            "password" => "a long password",
            "password_confirmation" => "a long passwort",
            "email" => "kb@example.org"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "claim-form"
      assert response =~ "does not match"
      refute get_session(conn, :user_token)
      assert Accounts.sign_in_state("kb") == :claimable
    end

    test "keeps the screen and the typed address when the email is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "kb",
            "password" => "a long password",
            "password_confirmation" => "a long password",
            "email" => "",
            "display_name" => "KB"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "claim-form"
      assert response =~ "can&#39;t be blank"
      assert response =~ ~s(value="KB")
      refute get_session(conn, :user_token)
      assert Accounts.sign_in_state("kb") == :claimable
    end

    test "keeps the screen when the password is too short", %{conn: conn} do
      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "kb",
            "password" => "short",
            "password_confirmation" => "short",
            "email" => "kb@example.org"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "claim-form"
      assert response =~ "at least 12 characters"
    end

    test "refuses a name that is not configured", %{conn: conn} do
      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "julia",
            "password" => "a long password",
            "password_confirmation" => "a long password",
            "email" => "j@example.org"
          }
        })

      assert html_response(conn, 200) =~ "do not match"
      refute get_session(conn, :user_token)
      assert Accounts.sign_in_state("julia") == :unknown
    end

    test "sends somebody whose name was claimed meanwhile to the sign-in form", %{conn: conn} do
      user_fixture(%{username: "kb"})

      conn =
        post(conn, ~p"/login/claim", %{
          "user" => %{
            "username" => "kb",
            "password" => "a long password",
            "password_confirmation" => "a long password",
            "email" => "x@example.org"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "login-form"
      assert response =~ "already exists"
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /login with an account" do
    test "signs in with the right username and password", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"username" => user.username, "password" => valid_password()}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)

      conn = get(conn, ~p"/admin/texts")
      assert html_response(conn, 200) =~ "Entries"
    end

    test "shows the missing-fields line when a field is empty", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{"user" => %{"username" => user.username, "password" => ""}})

      assert html_response(conn, 200) =~ "Both fields are required"
    end

    test "shows the mismatch line for wrong credentials, keeping the username", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"username" => user.username, "password" => "wrong password!"}
        })

      response = html_response(conn, 200)
      assert response =~ "do not match"
      assert response =~ user.username
      refute get_session(conn, :user_token)
    end

    test "refuses an account whose name left the configuration", %{conn: conn} do
      user = user_fixture()
      configure_admins([])

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"username" => user.username, "password" => valid_password()}
        })

      assert html_response(conn, 200) =~ "do not match"
      refute get_session(conn, :user_token)
    end
  end

  # The session cookie of a browser is gone when the browser closes. The
  # auth cookie is what carries the sign-in over that: two days, and
  # fourteen when the box is ticked.
  describe "the auth cookie" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    defp sign_in(conn, user, params \\ %{}) do
      post(
        conn,
        ~p"/login",
        %{
          "user" =>
            Map.merge(%{"username" => user.username, "password" => valid_password()}, params)
        }
      )
    end

    test "lasts two days without the box", %{conn: conn, user: user} do
      conn = sign_in(conn, user)

      assert redirected_to(conn) == ~p"/admin"
      assert %{max_age: 172_800} = conn.resp_cookies["_texttile_auth"]
    end

    test "lasts fourteen days with the box", %{conn: conn, user: user} do
      conn = sign_in(conn, user, %{"remember" => "true"})

      assert redirected_to(conn) == ~p"/admin"
      assert %{max_age: 1_209_600} = conn.resp_cookies["_texttile_auth"]
    end

    test "signs the browser in again after the session cookie is gone", %{conn: conn, user: user} do
      conn = sign_in(conn, user)
      auth = conn.resp_cookies["_texttile_auth"].value

      restarted =
        build_conn()
        |> Plug.Test.put_req_cookie("_texttile_auth", auth)
        |> get(~p"/admin")

      assert redirected_to(restarted) == ~p"/admin/texts"
    end

    test "a token the server has ended signs nobody in, and goes", %{conn: conn, user: user} do
      conn = sign_in(conn, user)
      auth = conn.resp_cookies["_texttile_auth"].value
      Accounts.delete_all_sessions(user)

      restarted =
        build_conn()
        |> Plug.Test.put_req_cookie("_texttile_auth", auth)
        |> get(~p"/admin")

      assert redirected_to(restarted) == ~p"/login"
      # the dead token is dropped where it was found: it never reaches
      # the session, and the cookie that carried it is taken away
      refute get_session(restarted, :user_token)
      assert %{max_age: 0} = restarted.resp_cookies["_texttile_auth"]
    end

    test "signing out takes it away", %{conn: conn, user: user} do
      conn = sign_in(conn, user)
      auth = conn.resp_cookies["_texttile_auth"].value

      out =
        build_conn()
        |> Plug.Test.put_req_cookie("_texttile_auth", auth)
        |> delete(~p"/logout")

      assert redirected_to(out) == ~p"/login"
      assert %{max_age: 0} = out.resp_cookies["_texttile_auth"]
    end
  end

  describe "DELETE /logout/all" do
    test "ends every session, in every browser", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      other_token = Accounts.create_session(user)
      TexttileWeb.Endpoint.subscribe(TexttileWeb.UserAuth.user_session_topic(other_token))

      conn = delete(conn, ~p"/logout/all")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
      assert Accounts.list_sessions(user) == []
      # the other browser's socket is told to go, not left on a dead token
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "works when not signed in", %{conn: conn} do
      conn = delete(conn, ~p"/logout/all")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "DELETE /logout" do
    test "ends only the current session", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      other_token = Accounts.create_session(user)

      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)

      assert [session] = Accounts.list_sessions(user)
      assert session.token == other_token
    end

    test "works when not signed in", %{conn: conn} do
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
