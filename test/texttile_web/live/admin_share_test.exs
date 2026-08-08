defmodule TexttileWeb.AdminShareTest do
  @moduledoc """
  What the admin area says about handing a text on: the blog password
  wherever a text is edited, the lines to pass on once it is live, and
  the way out to the site from every screen but the editor.
  """
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Lock
  alias Texttile.Settings

  setup :register_and_log_in_user

  # Lock processes outlive the SQL sandbox, so each test starts clean.
  setup do
    Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(&DynamicSupervisor.terminate_child(Lock.supervisor(), elem(&1, 1)))

    :ok
  end

  defp protect(password) do
    {:ok, _} = Settings.put(:site_visibility, "protected")
    {:ok, _} = Settings.put(:site_password, password)
    :ok
  end

  describe "the blog password in the editor" do
    # Once an entry is live the word stands inside the lines to pass on,
    # so the row of its own would say it twice.
    test "stands on a draft, and inside the lines once the entry is live", %{
      conn: conn,
      user: user
    } do
      protect("seaweed")

      {:ok, draft} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{draft}")
      assert has_element?(view, "#sharePasswordWord", "seaweed")

      for article <- [published_post(title: "The harbour"), published_page(title: "About")] do
        {:ok, view, html} = live(conn, ~p"/admin/texts/#{article}")
        refute has_element?(view, "#sharePassword")
        assert html =~ "The blog password is: seaweed"
      end
    end

    test "an open blog with no word says nothing at all", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      refute has_element?(view, "#sharePassword")
    end

    test "a word stored while the gate is open stands with the truth beside it", %{
      conn: conn,
      user: user
    } do
      {:ok, _} = Settings.put(:site_password, "seaweed")
      {:ok, article} = Articles.create_draft(user)

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      assert has_element?(view, "#sharePasswordWord", "seaweed")
      assert has_element?(view, "#sharePasswordHint", "The blog is open right now")
    end

    test "protected without a word says so instead of showing nothing", %{
      conn: conn,
      user: user
    } do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, article} = Articles.create_draft(user)

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      assert has_element?(view, "#sharePasswordMissing")
    end
  end

  describe "the lines to pass on" do
    test "arrive with the text going live, and carry the address", %{conn: conn, user: user} do
      {:ok, draft} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{draft}")
      refute has_element?(view, "#shareLines")

      article = published_post(title: "The harbour", slug: "the-harbour")
      {:ok, view, html} = live(conn, ~p"/admin/texts/#{article}")

      assert has_element?(view, "#shareLines")
      # Copy stands at the right end of the heading, where Reset does
      assert has_element?(view, "#shareBlock button[data-copy]", "Copy")
      assert html =~ "New on Texttile: The harbour"
      assert html =~ Articles.public_path(article)
      refute html =~ "The blog password is"
    end

    test "carry the blog password while the blog is protected", %{conn: conn} do
      protect("seaweed")
      article = published_post(title: "The harbour")

      {:ok, _view, html} = live(conn, ~p"/admin/texts/#{article}")
      assert html =~ "The blog password is: seaweed"
    end
  end

  describe "the way out to the site" do
    test "stands on every admin screen but the editor", %{conn: conn, user: user} do
      for path <- [
            ~p"/admin/texts",
            ~p"/admin/comments",
            ~p"/admin/newsletter",
            ~p"/admin/profile",
            ~p"/admin/settings",
            ~p"/admin/settings/import"
          ] do
        {:ok, view, _html} = live(conn, path)
        assert has_element?(view, ~s(#bar-view-site[href="/"])), "no way out on #{path}"
      end

      {:ok, article} = Articles.create_draft(user)
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      refute has_element?(view, "#bar-view-site")
    end
  end
end
