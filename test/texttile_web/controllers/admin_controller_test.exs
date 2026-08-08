defmodule TexttileWeb.AdminControllerTest do
  use TexttileWeb.ConnCase, async: true

  import Texttile.AccountsFixtures

  describe "the door of the admin area" do
    test "sends a signed-in admin to the entries", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin")
      assert redirected_to(conn) == ~p"/admin/texts"
    end

    test "sends a stranger to the sign-in", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
