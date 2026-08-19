defmodule TexttileWeb.AdminTest do
  # Not async: presence state is global to the node.
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures

  describe "the Here-now block" do
    test "shows the other admin's tabs as labelled jumps", %{conn: conn} do
      me = user_fixture(%{display_name: "kb"})
      other = user_fixture(%{display_name: "julia"})

      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
      {:ok, _other_texts, _} = live(other_conn, ~p"/admin/texts")
      {:ok, _other_profile, _} = live(other_conn, ~p"/admin/profile")

      {:ok, view, _html} = live(log_in_user(conn, me), ~p"/admin/texts")

      render_until(view, fn html -> html =~ "julia" end)
      assert has_element?(view, "#liveBlock", "julia")
      assert has_element?(view, ~s(#liveBlock a[href="/admin"]), "On the Entries overview")
      assert has_element?(view, ~s(#liveBlock a[href="/admin/profile"]), "In the profile")
      refute has_element?(view, "#liveBlock", "No one else right now.")
      refute has_element?(view, "#wmDot[hidden]")
    end

    test "a rename reaches the other admin's menu and the own other tab", %{conn: conn} do
      me = user_fixture(%{display_name: "kb"})
      other = user_fixture(%{display_name: "julia"})

      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
      {:ok, other_texts, _} = live(other_conn, ~p"/admin/texts")
      {:ok, other_profile, _} = live(other_conn, ~p"/admin/profile")

      {:ok, view, _html} = live(log_in_user(conn, me), ~p"/admin/texts")
      render_until(view, fn html -> html =~ "julia" end)

      other_profile
      |> form("#profile-form", %{"user" => %{"display_name" => "Julia W."}})
      |> render_change(%{"_target" => ["user", "display_name"]})

      # the other admin's menu follows...
      render_until(view, fn html -> html =~ "Julia W." end)
      assert has_element?(view, "#liveBlock", "Julia W.")
      refute has_element?(view, "#liveBlock .who", "julia")

      # ...and so does the renaming admin's second tab
      render_until(other_texts, fn html -> html =~ "Julia W." end)
      assert has_element?(other_texts, "#wmMe", "Julia W.")
    end
  end

  # Presence diffs arrive asynchronously; render until they did.
  describe "an open editor in the Here-now block" do
    test "says which text somebody writes in, as a jump to it", %{conn: conn} do
      me = user_fixture(%{display_name: "kb"})
      other = user_fixture(%{display_name: "julia"})

      {:ok, article} = Texttile.Articles.create_draft(other)
      {:ok, article} = Texttile.Articles.update_text(article, %{title: "Doors"})

      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
      {:ok, _editor, _} = live(other_conn, ~p"/admin/texts/#{article}")

      {:ok, view, _html} = live(log_in_user(conn, me), ~p"/admin/texts")
      render_until(view, fn html -> html =~ "Writing in" end)

      assert has_element?(
               view,
               ~s(#liveBlock a[href="/admin/texts/#{article.id}"]),
               "Writing in “Doors”"
             )
    end
  end

  defp render_until(view, fun) do
    eventually(fn -> fun.(render(view)) end)
    :ok
  end
end
