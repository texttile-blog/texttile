defmodule TexttileWeb.SiteSignedInCommentTest do
  @moduledoc """
  A comment written while signed in. The account carries the name and
  the address, so the form asks for neither, and the comment stands
  under the text at once.
  """
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Settings

  setup do
    {:ok, _} = Settings.put(:comments_require_confirmation, true)
    :ok
  end

  describe "the form of somebody signed in" do
    test "carries the name and the address of the account, and takes no typing", %{conn: conn} do
      user = user_fixture(%{display_name: "Katharina", email: "kb@example.org"})
      article = published_post()

      html =
        conn
        |> log_in_user(user)
        |> get(Articles.public_path(article))
        |> html_response(200)

      assert html =~ ~r/<input[^>]*id="comment-name"[^>]*value="Katharina"/
      assert html =~ ~r/<input[^>]*id="comment-email"[^>]*value="kb@example\.org"/

      # both fields are facts, not questions
      assert html =~ ~r/<input[^>]*id="comment-name"[^>]*disabled/
      assert html =~ ~r/<input[^>]*id="comment-email"[^>]*disabled/
      assert html =~ "You are signed in"
    end

    test "a reader who is not signed in still gets two empty fields", %{conn: conn} do
      article = published_post()

      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      refute html =~ ~r/<input[^>]*id="comment-name"[^>]*disabled/
      refute html =~ "You are signed in"
    end
  end

  # Every address a "New comment" mail reached. The mails leave in
  # tasks of their own, so the first one is waited for and the rest are
  # drained behind it.
  defp drain_comment_mails(reached \\ [], wait \\ 2000) do
    receive do
      {:email, %Swoosh.Email{subject: "New comment" <> _, to: to}} ->
        drain_comment_mails(reached ++ Enum.map(to, &elem(&1, 1)), 400)

      {:email, _other} ->
        drain_comment_mails(reached, wait)
    after
      wait -> reached
    end
  end

  describe "posting while signed in" do
    test "stores the account's name and address, and points the comment at it", %{conn: conn} do
      user = user_fixture(%{display_name: "Katharina", email: "kb@example.org"})
      article = published_post()

      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{"body" => "My own text, my own words."})

      assert [comment] = Comments.for_article(article.id)
      assert comment.name == "Katharina"
      assert comment.address.email == "kb@example.org"
      assert comment.user_id == user.id
      assert comment.body == "My own text, my own words."
    end

    test "the comment stands under the text at once, with no mail asking for anything", %{
      conn: conn
    } do
      user = user_fixture(%{display_name: "Katharina", email: "kb@example.org"})
      article = published_post()

      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{"body" => "Straight under the text."})

      assert [comment] = Comments.for_article(article.id)
      assert Comments.shown_to_readers?(comment)

      # Nothing waits for a link, because the account already answered
      # for the address: it stands confirmed, and no mail asked for it.
      assert comment.address.confirmed_at
      assert is_nil(comment.address.confirmation_mailed_at)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "Straight under the text."
    end

    test "a name and an address sent along the form are ignored", %{conn: conn} do
      user = user_fixture(%{display_name: "Katharina", email: "kb@example.org"})
      article = published_post()

      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{
        "name" => "Somebody Else",
        "email" => "stranger@example.org",
        "body" => "Not under that name."
      })

      assert [comment] = Comments.for_article(article.id)
      assert comment.name == "Katharina"
      assert comment.address.email == "kb@example.org"
    end

    test "the name of an account leads to this blog, whatever the form sends", %{conn: conn} do
      user = user_fixture()
      article = published_post()

      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{
        "body" => "From the house.",
        "website" => "https://somewhere-else.example"
      })

      # nothing of it is stored: the link is the site itself, and it
      # follows the site wherever it moves
      assert [comment] = Comments.for_article(article.id)
      assert comment.website == nil

      html = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ "somewhere-else.example"
      assert html =~ ~s(<a href="/" class="writer-out")
    end

    test "the time trap and the honeypot let an account through", %{conn: conn} do
      user = user_fixture()
      article = published_post()

      # No stamp at all, and a filled honeypot: a stranger loses both
      # ways, somebody signed in is no stranger.
      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{
        "body" => "Through the traps.",
        "url" => "https://spam.example"
      })

      assert [comment] = Comments.for_article(article.id)
      assert comment.body == "Through the traps."
    end

    test "nobody is mailed about their own comment, everybody else is", %{conn: conn} do
      {:ok, _} = Settings.put(:notify_on_comment, true)
      author = user_fixture(%{username: "author", email: "author@example.org"})
      other = user_fixture(%{username: "other", email: "other@example.org"})
      article = published_post()

      # The mail leaves in a task of its own, so it has to land here.

      conn
      |> log_in_user(author)
      |> post(~p"/comments/#{article.id}", %{"body" => "One mail, not two."})

      # Everybody the mail reached, once the whole run is through.
      reached = drain_comment_mails()

      assert other.email in reached
      refute author.email in reached
    end

    test "the comment outlives the account that wrote it", %{conn: conn} do
      author = user_fixture(%{username: "author", display_name: "Katharina"})
      keeper = user_fixture(%{username: "keeper"})
      article = published_post()

      conn
      |> log_in_user(author)
      |> post(~p"/comments/#{article.id}", %{"body" => "Still here afterwards."})

      {:ok, _} = Texttile.Accounts.delete_user(author, by: keeper)

      assert [comment] = Comments.for_article(article.id)
      assert is_nil(comment.user_id)
      assert comment.name == "Katharina"
      assert comment.body == "Still here afterwards."
    end

    test "words that are empty still get the form back", %{conn: conn} do
      user = user_fixture()
      article = published_post()

      html =
        conn
        |> log_in_user(user)
        |> post(~p"/comments/#{article.id}", %{"body" => "   "})
        |> html_response(200)

      assert html =~ "comment-error"
      assert Comments.for_article(article.id) == []
    end
  end
end
