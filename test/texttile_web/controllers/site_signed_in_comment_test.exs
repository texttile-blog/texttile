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
    Texttile.RateLimiter.reset()
    on_exit(&Texttile.RateLimiter.reset/0)
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

    test "the time trap and the honeypot let an account through", %{conn: conn} do
      user = user_fixture()
      article = published_post()

      # No stamp at all, and a filled honeypot: a stranger loses both
      # ways, somebody signed in is no stranger.
      conn
      |> log_in_user(user)
      |> post(~p"/comments/#{article.id}", %{
        "body" => "Through the traps.",
        "website" => "https://spam.example"
      })

      assert [comment] = Comments.for_article(article.id)
      assert comment.body == "Through the traps."
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
