defmodule TexttileWeb.CommentsLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.ArticlesFixtures

  alias Texttile.Comments
  alias Texttile.Settings

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

  test "an empty overview says every comment will show up here", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    assert has_element?(view, "#crumb", "Comments")
    assert has_element?(view, "#commentsList", "No comments yet, anywhere")
    assert has_element?(view, "#commentsRule", "No captcha, ever")
  end

  test "lists the latest comments across texts with their marks and jumps", %{conn: conn} do
    a = published_post(title: "Harbor mornings")
    b = published_post(title: "Doors of Vilnius")
    waiting = post!(a)
    confirmed = post!(b, %{"email" => "jens@example.org", "body" => "Good set."})
    {:ok, _} = Comments.confirm(confirmed.address.token)

    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    assert has_element?(view, "#comment-#{waiting.id}", "not confirmed yet")
    assert has_element?(view, "#comment-#{waiting.id} a", "Harbor mornings")
    assert has_element?(view, "#comment-#{confirmed.id}", "Good set.")
    refute has_element?(view, "#comment-#{confirmed.id} .wait")

    assert has_element?(view, "#commentsSub", "2 comments across all texts")
    assert has_element?(view, "#commentsSub", "1 comment waits for the reader")
  end

  test "a ninth comment moves the oldest behind the overflow line", %{conn: conn} do
    article = published_post()

    for n <- 1..9 do
      post!(article, %{"email" => "reader#{n}@example.org", "body" => "Words #{n}"})
    end

    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    assert has_element?(view, "#commentsList", "Words 9")
    refute has_element?(view, "#commentsList", "Words 1")
    assert has_element?(view, "#commentsList", "and 1 more on their texts.")
  end

  test "delete removes the comment silently, live for the whole desk", %{conn: conn} do
    article = published_post()
    comment = post!(article)

    {:ok, view, _html} = live(conn, ~p"/admin/comments")
    {:ok, other, _html} = live(conn, ~p"/admin/comments")

    view
    |> element("#comment-#{comment.id} button", "Delete")
    |> render_click()

    refute has_element?(view, "#comment-#{comment.id}")
    refute has_element?(other, "#comment-#{comment.id}")
    assert Comments.for_article(article.id) == []
  end

  test "a fresh comment arrives without a reload", %{conn: conn} do
    article = published_post()
    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    comment = post!(article)
    assert has_element?(view, "#comment-#{comment.id}")
  end

  test "the rule follows the setting as it changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/comments")
    assert has_element?(view, "#commentsRule", "Readers confirm their email first")

    {:ok, _} = Settings.put(:comments_require_confirmation, false)
    assert has_element?(view, "#commentsRule", "nobody confirms anything")
  end
end
