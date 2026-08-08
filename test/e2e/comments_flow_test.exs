defmodule TexttileWeb.E2E.CommentsFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
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

    # The desk: the overview carries it, its jump opens the text's tab,
    # Delete takes it out.
    conn
    |> sign_in()
    |> visit("/admin/comments")
    |> assert_has("#commentsSub", text: "1 comment across all texts")
    |> assert_has("#commentsList", text: "Grandma Christel")
    |> click_link("Harbor mornings")
    |> assert_has("#tp-comments", text: "More of the dog, please.")
    |> click_button("Delete")
    |> assert_has("#tp-comments", text: "No comments yet.")

    assert Texttile.Comments.total_count() == 0
  end

  test "the desk releases one comment, rewrites it, trashes it and takes it back", %{conn: conn} do
    user_fixture(%{username: "kb"})
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    # The reader writes and never touches the mail: the comment stands
    # for its own writer and for nobody else.
    session =
      conn
      |> visit(Articles.public_path(article))
      |> fill_in("Name", with: "Grandma Christel")
      |> fill_in("Email", with: "christel@example.org")
      |> fill_in("Comment", with: "More of the dog, please.")
      |> click_button("Post comment")
      |> assert_has("#comment-note", text: "Sent. Follow the link in your mail")
      |> assert_has("#comments", text: "waiting for your confirmation")
      |> assert_has("#comment-count", text: "Comments")
      |> refute_has("#comment-count", text: "1 comment")

    # The desk lets this one comment through, and the text carries it.
    session =
      session
      |> sign_in()
      |> visit("/admin/comments")
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
      |> visit("/admin/comments")
      |> click_button("Edit")
      |> fill_in("The words of the comment", with: "Less of the dog, please.")
      |> click_button("Save")
      |> assert_has("#commentsList", text: "Less of the dog, please.")
      |> assert_has("#commentsList", text: "edited")
      |> visit(Articles.public_path(article))
      |> assert_has("#comments", text: "Less of the dog, please.")
      |> refute_has("#comments", text: "More of the dog, please.")

    # Delete is the trash now: out of the text, kept on the desk.
    session =
      session
      |> visit("/admin/comments")
      |> click_button("Delete")
      |> assert_has("#commentsTrash", text: "Less of the dog, please.")
      |> assert_has("#commentsTrash", text: "goes for good")
      |> visit(Articles.public_path(article))
      |> refute_has("#comments", text: "Less of the dog, please.")

    # And the way back puts it exactly where it stood.
    session
    |> visit("/admin/comments")
    |> click_button("Restore")
    |> refute_has("#commentsTrash")
    |> assert_has("#commentsList", text: "Less of the dog, please.")
    |> visit(Articles.public_path(article))
    |> assert_has("#comment-count", text: "1 comment")
    |> assert_has("#comments", text: "Less of the dog, please.")

    assert Texttile.Comments.total_count() == 1
    assert Texttile.Comments.trashed_count() == 0
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end
end
