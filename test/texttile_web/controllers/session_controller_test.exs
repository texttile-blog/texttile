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
      # the box that asks for the longer session, under the name the
      # tests below hand to the controller
      assert response =~ ~s(name="user[remember]")
    end

    # A fresh installation cannot let anybody choose a password here:
    # the link in the inbox does that. The screen says where to look.
    test "says why nobody can sign in yet on a fresh installation", %{conn: conn} do
      configure_admin_emails(["margarethe@example.org"])
      response = conn |> get(~p"/login") |> html_response(200)

      assert response =~ "login-form"
      assert response =~ "login-nobody"
      refute response =~ "margarethe@example.org"
    end

    test "sends a signed-in admin to the admin area", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/login")
      assert redirected_to(conn) == ~p"/admin"
    end
  end

  describe "POST /login" do
    test "signs in with the right address and password", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_password()}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)

      conn = get(conn, ~p"/admin/texts")
      assert html_response(conn, 200) =~ "Entries"
    end

    test "takes the address in any case", %{conn: conn} do
      user_fixture(%{email: "kb@example.org"})

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => " KB@Example.ORG ", "password" => valid_password()}
        })

      assert redirected_to(conn) == ~p"/admin"
    end

    test "shows the missing-fields line when a field is empty", %{conn: conn} do
      user = user_fixture()

      conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => ""}})

      assert html_response(conn, 200) =~ "Both fields are required"
    end

    test "shows the mismatch line for a wrong password, keeping the address", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "wrong password!"}
        })

      response = html_response(conn, 200)
      assert response =~ "do not match"
      assert response =~ user.email
      refute get_session(conn, :user_token)
    end

    # The screen never says who has an account here, so an address
    # without one reads exactly like a wrong password.
    test "answers an address without an account like a wrong password", %{conn: conn} do
      user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "stranger@example.org", "password" => "guess it"}
        })

      assert html_response(conn, 200) =~ "do not match"
      refute get_session(conn, :user_token)
    end

    # The window this closes: an account that was invited and has not
    # been opened yet belongs to its inbox, not to whoever is early.
    test "no password opens an account that is still waiting for its first one", %{conn: conn} do
      user_fixture()
      invited_user_fixture("anna@example.org")

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "anna@example.org", "password" => "a long password"}
        })

      assert html_response(conn, 200) =~ "do not match"
      refute get_session(conn, :user_token)
    end

    # ADMIN_USERS adds accounts, it does not hold them: an address that
    # leaves the variable signs in as before.
    test "signs in an account whose address left the configuration", %{conn: conn} do
      user = user_fixture()
      configure_admin_emails([])

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_password()}
        })

      assert redirected_to(conn) == ~p"/admin"
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
          "user" => Map.merge(%{"email" => user.email, "password" => valid_password()}, params)
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

      TexttileWeb.Endpoint.subscribe(
        TexttileWeb.UserAuth.user_session_topic(Accounts.session_fingerprint(other_token))
      )

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
      assert session.token_hash == Accounts.session_fingerprint(other_token)
    end

    test "works when not signed in", %{conn: conn} do
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  # There is no screen here that creates an account, so the old way in
  # is gone with it.
  describe "the password screen of the older sign-in" do
    test "is not a route any more", %{conn: conn} do
      assert conn |> get("/login/claim?invite=whatever") |> response(404)
    end
  end

  describe "the brake on the password doors" do
    test "stops the sign-in after a few tries", %{conn: conn} do
      user = user_fixture()

      for _try <- 1..Accounts.door_limiter_per_minute() do
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "wrong password!"}
        })
      end

      # the right password too: a guesser who lands on it in the same
      # minute is still a guesser
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_password()}
        })

      assert html_response(conn, 200) =~ "Too many tries"
      refute get_session(conn, :user_token)
    end
  end
end
