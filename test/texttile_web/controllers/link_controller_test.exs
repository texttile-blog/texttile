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
      user = user_fixture(%{username: "julia"})
      conn = get(conn, ~p"/link/#{mailed_link(user)}")

      html = html_response(conn, 200)
      assert html =~ "julia"
      assert html =~ "New password"
    end

    test "a dead link says so", %{conn: conn} do
      conn = get(conn, ~p"/link/not-a-real-token")
      assert html_response(conn, 200) =~ "This link does not work any more"
    end
  end

  describe "POST /link/:token" do
    test "sets the password and signs the person in", %{conn: conn} do
      user = user_fixture(%{username: "julia"})
      token = mailed_link(user)

      conn =
        post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "a long enough password"}})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
      assert {:ok, _} = Accounts.authenticate_user("julia", "a long enough password")
    end

    test "a short password stays on the form and says why", %{conn: conn} do
      user = user_fixture()
      token = mailed_link(user)

      conn = post(conn, ~p"/link/#{token}", %{"user" => %{"password" => "short"}})

      assert html_response(conn, 200) =~ "at least 12 characters"
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
      assert_email_sent(to: [{user.username, "kb@example.org"}])
    end

    test "an unknown address gets no mail; the answer reads the same", %{conn: conn} do
      conn = post(conn, ~p"/forgot", %{"user" => %{"email" => "nobody@example.org"}})
      assert html_response(conn, 200) =~ "on its way"
      assert_no_email_sent()
    end
  end
end
