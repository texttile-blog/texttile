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

  test "delete asks first, and the words stay while the question stands", %{conn: conn} do
    article = published_post()
    comment = post!(article)

    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    view |> element("#comment-#{comment.id} button", "Delete") |> render_click()

    assert has_element?(view, "#dialog", "Delete the comment of Grandma Christel?")
    assert has_element?(view, "#dialog", "keeps it for 30 days")
    assert has_element?(view, "#comment-#{comment.id}")
    assert Comments.total_count() == 1

    view |> element("#dialog-cancel") |> render_click()

    refute has_element?(view, "#dialog")
    assert Comments.total_count() == 1
  end

  test "delete removes the comment silently, live for the whole desk", %{conn: conn} do
    article = published_post()
    comment = post!(article)

    {:ok, view, _html} = live(conn, ~p"/admin/comments")
    {:ok, other, _html} = live(conn, ~p"/admin/comments")

    view |> element("#comment-#{comment.id} button", "Delete") |> render_click()
    view |> element("#dialog-ok") |> render_click()

    refute has_element?(view, "#dialog")
    refute has_element?(view, "#comment-#{comment.id}")
    refute has_element?(other, "#comment-#{comment.id}")
    assert Comments.for_article(article.id) == []
  end

  test "two desks deleting the same comment is no crash", %{conn: conn} do
    article = published_post()
    comment = post!(article)

    {:ok, one, _html} = live(conn, ~p"/admin/comments")
    {:ok, two, _html} = live(conn, ~p"/admin/comments")

    one |> element("#comment-#{comment.id} button", "Delete") |> render_click()
    one |> element("#dialog-ok") |> render_click()

    render_click(two, "delete_comment", %{"id" => comment.id})
    render_click(two, "confirm_delete_comment", %{"id" => comment.id})

    refute has_element?(two, "#comment-#{comment.id}")
    assert Comments.total_count() == 0
  end

  test "the words keep the line breaks the reader typed", %{conn: conn} do
    article = published_post()
    comment = post!(article, %{"body" => "One line.\n\nAnd another one."})

    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    html = view |> element("#comment-#{comment.id} p.comment-body") |> render()
    assert html =~ "One line.\n\nAnd another one."
    refute html =~ ">\n  One line"
  end

  test "a fresh comment arrives without a reload", %{conn: conn} do
    article = published_post()
    {:ok, view, _html} = live(conn, ~p"/admin/comments")

    comment = post!(article)
    assert has_element?(view, "#comment-#{comment.id}")
  end

  describe "the trash" do
    test "delete puts the comment in the trash, restore brings it back", %{conn: conn} do
      article = published_post(title: "Harbor mornings")
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      refute has_element?(view, "#commentsTrash")

      view |> element("#comment-#{comment.id} button", "Delete") |> render_click()
      view |> element("#dialog-ok") |> render_click()

      refute has_element?(view, "#comment-#{comment.id}")
      assert has_element?(view, "#commentsTrash #trash-#{comment.id}", "More of the dog")
      assert has_element?(view, "#commentsTrash", "Harbor mornings")
      assert has_element?(view, "#commentsTrash", "goes for good")

      view |> element("#trash-#{comment.id} button", "Restore") |> render_click()

      refute has_element?(view, "#commentsTrash")
      assert has_element?(view, "#comment-#{comment.id}")
      assert Enum.map(Comments.for_article(article.id), & &1.id) == [comment.id]
    end

    test "the trash of one screen shows on the other", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      {:ok, other, _html} = live(conn, ~p"/admin/comments")

      view |> element("#comment-#{comment.id} button", "Delete") |> render_click()
      view |> element("#dialog-ok") |> render_click()
      assert has_element?(other, "#trash-#{comment.id}")

      view |> element("#trash-#{comment.id} button", "Restore") |> render_click()
      refute has_element?(other, "#trash-#{comment.id}")
      assert has_element?(other, "#comment-#{comment.id}")
    end

    test "the trash carries the newest deleted and counts the rest", %{conn: conn} do
      article = published_post()

      for n <- 1..9 do
        comment = post!(article, %{"email" => "reader#{n}@example.org", "body" => "Words #{n}"})
        {:ok, _} = Comments.delete_comment(comment)
      end

      {:ok, view, _html} = live(conn, ~p"/admin/comments")

      assert has_element?(view, "#commentsTrash", "Words 9")
      refute has_element?(view, "#commentsTrash", "Words 1")
      assert has_element?(view, "#commentsTrash", "and 1 deleted earlier")
      assert has_element?(view, "#commentsTrash", "9 deleted comments wait here")
    end

    test "a comment another admin restored first is no crash", %{conn: conn} do
      article = published_post()
      comment = post!(article)
      {:ok, _} = Comments.delete_comment(comment)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      {:ok, _} = Comments.restore_comment(comment.id)

      render_click(view, "restore_comment", %{"id" => comment.id})
      refute has_element?(view, "#trash-#{comment.id}")
    end
  end

  describe "edit" do
    test "changes the words in place and marks the comment", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      {:ok, other, _html} = live(conn, ~p"/admin/comments")

      view |> element("#comment-#{comment.id} button", "Edit") |> render_click()

      view
      |> form("#edit-comment-#{comment.id}", %{"body" => "Less of the dog, please."})
      |> render_submit()

      assert has_element?(view, "#comment-#{comment.id}", "Less of the dog, please.")
      assert has_element?(view, "#comment-#{comment.id}", "edited")
      refute has_element?(view, "#edit-comment-#{comment.id}")
      assert has_element?(other, "#comment-#{comment.id}", "Less of the dog, please.")
    end

    test "cancel leaves the words as they were", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      view |> element("#comment-#{comment.id} button", "Edit") |> render_click()
      view |> element("#edit-comment-#{comment.id} button", "Cancel") |> render_click()

      refute has_element?(view, "#edit-comment-#{comment.id}")
      assert has_element?(view, "#comment-#{comment.id}", "More of the dog, please.")
      refute has_element?(view, "#comment-#{comment.id}", "edited")
    end

    test "empty words keep the form open and say so", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      view |> element("#comment-#{comment.id} button", "Edit") |> render_click()

      view |> form("#edit-comment-#{comment.id}", %{"body" => "   "}) |> render_submit()

      assert has_element?(view, "#edit-comment-#{comment.id}", "A comment needs some words")
      assert Comments.get_comment!(comment.id).body == "More of the dog, please."
    end

    test "words beyond the limit say so, and not that there are none", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      view |> element("#comment-#{comment.id} button", "Edit") |> render_click()

      view
      |> form("#edit-comment-#{comment.id}", %{"body" => String.duplicate("b", 4001)})
      |> render_submit()

      assert has_element?(view, "#edit-comment-#{comment.id}", "4000 characters at most")
      refute has_element?(view, "#edit-comment-#{comment.id}", "needs some words")
      assert Comments.get_comment!(comment.id).body == "More of the dog, please."
    end

    test "only one comment is open at a time", %{conn: conn} do
      article = published_post()
      one = post!(article)
      two = post!(article, %{"email" => "jens@example.org", "body" => "Good set."})

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      view |> element("#comment-#{one.id} button", "Edit") |> render_click()
      view |> element("#comment-#{two.id} button", "Edit") |> render_click()

      refute has_element?(view, "#edit-comment-#{one.id}")
      assert has_element?(view, "#edit-comment-#{two.id}")
    end
  end

  describe "release" do
    test "lets one comment through and leaves the address waiting", %{conn: conn} do
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      assert has_element?(view, "#comment-#{comment.id}", "not confirmed yet")

      view |> element("#comment-#{comment.id} button", "Release") |> render_click()

      refute has_element?(view, "#comment-#{comment.id} .wait")
      refute has_element?(view, "#comment-#{comment.id} button", "Release")
      # not "every one of them is confirmed": this one never was
      assert has_element?(view, "#commentsSub", "Readers see every one of them")
      refute has_element?(view, "#commentsSub", "confirmed")
      assert Comments.shown_to_readers?(Comments.get_comment!(comment.id))

      # the next comment from the same address waits like every other
      later = post!(article, %{"body" => "And another thing"})
      assert has_element?(view, "#comment-#{later.id}", "not confirmed yet")
    end

    test "a confirmed comment is never offered a release", %{conn: conn} do
      article = published_post()
      comment = post!(article)
      {:ok, _} = Comments.confirm(comment.address.token)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      refute has_element?(view, "#comment-#{comment.id} button", "Release")
    end

    test "with the setting off nothing waits and nothing is released", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post()
      comment = post!(article)

      {:ok, view, _html} = live(conn, ~p"/admin/comments")
      refute has_element?(view, "#comment-#{comment.id} button", "Release")
    end
  end

  test "the rule follows the setting as it changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/comments")
    assert has_element?(view, "#commentsRule", "Readers confirm their email first")

    {:ok, _} = Settings.put(:comments_require_confirmation, false)
    assert has_element?(view, "#commentsRule", "nobody confirms anything")
  end
end
