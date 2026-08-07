defmodule TexttileWeb.EditorCommentsTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Comments

  setup :register_and_log_in_user

  defp post!(article, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "name" => "Grandma Christel",
          "email" => "christel@example.org",
          "body" => "More of the dog, please."
        },
        attrs
      )

    {:ok, comment} = Comments.post(article, attrs, confirm_url: &"http://test/#{&1}")
    comment
  end

  test "the Comments tab carries the count and the list", %{conn: conn} do
    article = published_post()
    waiting = post!(article)
    confirmed = post!(article, %{"email" => "jens@example.org", "body" => "Good set."})
    {:ok, _} = Comments.confirm(confirmed.address.token)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}")
    assert has_element?(view, "nav .tab .cnt", "2")

    view |> element("nav .tab", "Comments") |> render_click()

    assert has_element?(view, "#tp-comments #comment-#{waiting.id}", "not confirmed yet")
    assert has_element?(view, "#tp-comments #comment-#{confirmed.id}", "Good set.")
    refute has_element?(view, "#comment-#{confirmed.id} .wait")
    assert has_element?(view, "#tp-comments", "1 comment is still out of the text")
  end

  test "an empty tab explains the rule", %{conn: conn} do
    article = published_post()
    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}")

    view |> element("nav .tab", "Comments") |> render_click()
    assert has_element?(view, "#tp-comments", "No comments yet.")
    assert has_element?(view, "#tp-comments", "No captcha, ever")
  end

  test "?tab=comments opens the tab straight from the overview's jump", %{conn: conn} do
    article = published_post()
    post!(article)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=comments")
    assert has_element?(view, "#tp-comments")
  end

  test "delete takes the comment out of the text", %{conn: conn} do
    article = published_post()
    comment = post!(article)

    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=comments")

    view
    |> element("#comment-#{comment.id} button", "Delete")
    |> render_click()

    refute has_element?(view, "#comment-#{comment.id}")
    assert Comments.for_article(article.id) == []
  end

  test "a comment arriving on the open text shows up live", %{conn: conn} do
    article = published_post()
    {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article.id}?tab=comments")

    comment = post!(article)
    assert has_element?(view, "#comment-#{comment.id}")

    # a comment on another text stays out of this editor
    other = published_post()
    stranger = post!(other, %{"email" => "other@example.org"})
    refute has_element?(view, "#comment-#{stranger.id}")
  end
end
