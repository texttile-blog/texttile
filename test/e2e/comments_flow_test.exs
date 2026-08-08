defmodule TexttileWeb.E2E.CommentsFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
  import TexttileWeb.E2E, only: [sign_in: 1, open: 2]
  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  # Every test in the run knocks from the same address, so the browser
  # must not meet a limit another test spent.
  setup do
    Texttile.RateLimiter.reset()
    :ok
  end

  test "a reader comments, confirms by mail, the admin reads and deletes", %{conn: conn} do
    user_fixture(%{username: "kb"})
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    # Mails from the server processes land in this test process.
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    # The reader writes. The comment waits, visible only to its reader.
    conn
    |> visit(Articles.public_path(article))
    |> assert_has("#comments", text: "Post a comment")
    |> refute_has("#comment-count")
    |> fill_in("Name", with: "Grandma Christel")
    |> fill_in("Email", with: "christel@example.org")
    |> fill_in("Comment", with: "More of the dog, please.")
    |> click_button("Post comment")
    |> assert_has("#comment-note", text: "Sent. Follow the link in your mail")
    |> assert_has("#comments", text: "waiting for your confirmation")

    # The mailed link publishes the comment for everybody.
    assert_receive {:email, %Swoosh.Email{} = mail}, 2000
    assert mail.to == [{"Grandma Christel", "christel@example.org"}]
    [link] = Regex.run(~r"http://[^\s]+/comments/confirm/[^\s]+", mail.text_body)

    conn
    |> visit(link)
    |> assert_has("#comments h2", text: "1 comment")
    |> assert_has("#comments", text: "More of the dog, please.")
    |> refute_has("#comments .wait")

    # The admin area: the overview carries it, its jump opens the
    # text's tab, Delete takes it out.
    conn
    |> sign_in()
    |> open("/admin/comments")
    |> assert_has("#commentsSub", text: "1 comment across all texts")
    |> assert_has("#commentsList", text: "Grandma Christel")
    |> click_link("Harbor mornings")
    |> assert_has("#tp-comments", text: "More of the dog, please.")
    |> click_button("Delete")
    |> assert_has("#dialog", text: "Delete the comment of Grandma Christel?")
    |> click_button("Delete the comment")
    |> assert_has("#tp-comments", text: "No comments yet.")

    assert Texttile.Comments.total_count() == 0
  end

  test "an admin releases one comment, rewrites it, trashes it and takes it back", %{conn: conn} do
    user_fixture(%{username: "kb"})
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    # A reader wrote and never touched the mail. The form itself is the
    # test above; this one starts where that one ends, and it knocks on
    # nothing, so it never spends the rate limit a browser test running
    # beside it is about to need.
    {:ok, _} =
      Texttile.Comments.post(
        article,
        %{
          "name" => "Grandma Christel",
          "email" => "christel@example.org",
          "body" => "More of the dog, please."
        },
        confirm_url: &"http://localhost/comments/confirm/#{&1}"
      )

    # Nobody sees it while it waits, not even the count.
    session =
      conn
      |> visit(Articles.public_path(article))
      |> refute_has("#comments", text: "More of the dog, please.")
      |> refute_has("#comment-count")

    # The admin lets this one comment through, and the text carries it.
    session =
      session
      |> sign_in()
      |> open("/admin/comments")
      |> assert_has("#commentsList", text: "not confirmed yet")
      |> click_button("Release")
      |> assert_has("#commentsList", text: "let through")
      |> refute_has("#commentsList .wait")
      |> visit(Articles.public_path(article))
      |> assert_has("#comment-count", text: "1 comment")
      |> refute_has("#comments", text: "waiting for your confirmation")

    # And rewrites the words the reader sent.
    session =
      session
      |> open("/admin/comments")
      |> click_button("Edit")
      |> fill_in("The words of the comment", with: "Less of the dog, please.")
      |> click_button("Save")
      |> assert_has("#commentsList", text: "Less of the dog, please.")
      |> assert_has("#commentsList", text: "edited")
      |> visit(Articles.public_path(article))
      |> assert_has("#comments", text: "Less of the dog, please.")
      |> refute_has("#comments", text: "More of the dog, please.")

    # Delete is the trash now: out of the text, kept in the admin area.
    session =
      session
      |> open("/admin/comments")
      |> click_button("Delete")
      |> click_button("Delete the comment")
      |> assert_has("#commentsTrash", text: "Less of the dog, please.")
      |> assert_has("#commentsTrash", text: "goes for good")
      |> visit(Articles.public_path(article))
      |> refute_has("#comments", text: "Less of the dog, please.")

    # And the way back puts it exactly where it stood.
    session
    |> open("/admin/comments")
    |> click_button("Restore")
    |> refute_has("#commentsTrash")
    |> assert_has("#commentsList", text: "Less of the dog, please.")
    |> visit(Articles.public_path(article))
    |> assert_has("#comment-count", text: "1 comment")
    |> assert_has("#comments", text: "Less of the dog, please.")

    assert Texttile.Comments.total_count() == 1
    assert Texttile.Comments.trashed_count() == 0
  end

  test "an admin comments under their own name, and the list counts it", %{conn: conn} do
    user = user_fixture(%{username: "kb", display_name: "Katharina"})
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    session = conn |> sign_in() |> visit(Articles.public_path(article))

    # The two fields carry the account and take no typing.
    session
    |> assert_has("#comment-name[disabled][value='Katharina']")
    |> assert_has("#comment-email[disabled][value='#{user.email}']")
    |> assert_has("#comments", text: "You are signed in")
    |> fill_in("Comment", with: "Writing under my own name.")
    |> click_button("Post comment")
    # No link to follow: it stands under the text at once.
    |> assert_has("#comment-count", text: "1 comment")
    |> assert_has("#comments", text: "Writing under my own name.")
    |> refute_has("#comments", text: "waiting for your confirmation")

    # And the count travels to both lists.
    session
    |> visit("/blog")
    |> assert_has("#texts", text: "1 comment")
    |> open("/admin")
    |> assert_has("#cards", text: "1 comment")

    assert [comment] = Texttile.Comments.for_article(article.id)
    assert comment.user_id == user.id
  end
end
