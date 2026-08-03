defmodule TexttileWeb.SetupControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures

  alias Texttile.Boot

  @window_ms 30 * 60 * 1000

  setup do
    Boot.set_started_at(System.system_time(:millisecond))
    on_exit(fn -> Boot.set_started_at(System.system_time(:millisecond)) end)
    :ok
  end

  describe "GET /setup" do
    test "shows the form on a fresh install inside the window", %{conn: conn} do
      response = conn |> get(~p"/setup") |> html_response(200)
      assert response =~ "setup-form"
      assert response =~ "First-run setup"
    end

    test "shows the closed screen outside the window", %{conn: conn} do
      Boot.set_started_at(System.system_time(:millisecond) - @window_ms - 1)
      response = conn |> get(~p"/setup") |> html_response(200)
      assert response =~ "The setup window is closed"
      refute response =~ "setup-form"
    end

    test "sends a set-up site to the sign-in screen", %{conn: conn} do
      user_fixture()
      conn = get(conn, ~p"/setup")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "POST /setup" do
    test "creates the admin, signs in and mails the confirmation", %{conn: conn} do
      conn =
        post(conn, ~p"/setup", %{
          "user" => %{
            "username" => "kb",
            "email" => "kb@example.org",
            "password" => "a long password"
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)

      assert_email_sent(fn email ->
        email.to == [{"kb", "kb@example.org"}]
      end)

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Texts"
    end

    test "re-renders the form with the errors", %{conn: conn} do
      response =
        conn
        |> post(~p"/setup", %{
          "user" => %{"username" => "Not Valid!", "email" => "nope", "password" => "short"}
        })
        |> html_response(200)

      assert response =~ "lower case letters"
      assert response =~ "must be an email address"
      assert response =~ "at least 12 characters"
    end

    test "refuses outside the window", %{conn: conn} do
      Boot.set_started_at(System.system_time(:millisecond) - @window_ms - 1)

      response =
        conn
        |> post(~p"/setup", %{"user" => valid_user_attributes() |> stringify()})
        |> html_response(200)

      assert response =~ "The setup window is closed"
    end

    test "refuses once an account exists", %{conn: conn} do
      user_fixture()
      conn = post(conn, ~p"/setup", %{"user" => valid_user_attributes() |> stringify()})
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "the desk without a session" do
    test "a fresh install lands on setup", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/setup"
    end

    test "a set-up site lands on sign-in", %{conn: conn} do
      user_fixture()
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/login"
    end
  end

  defp stringify(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
