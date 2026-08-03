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

    test "sends a fresh install to the setup screen", %{conn: conn} do
      conn = get(conn, ~p"/login")
      assert redirected_to(conn) == ~p"/setup"
    end

    test "sends a signed-in admin to the desk", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/login")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /login" do
    test "signs in with the right username and password", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"username" => user.username, "password" => valid_password()}
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Texts"
    end

    test "shows the missing-fields line when a field is empty", %{conn: conn} do
      user_fixture()
      conn = post(conn, ~p"/login", %{"user" => %{"username" => "kb", "password" => ""}})
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
