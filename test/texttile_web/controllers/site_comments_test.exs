defmodule TexttileWeb.SiteCommentsTest do
  use TexttileWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Settings

  @form %{
    "name" => "Grandma Christel",
    "email" => "christel@example.org",
    "body" => "More of the dog, please."
  }

  # Every test posts from its own address, so the shared rate limiter
  # never counts one test's comments against another's. The header only
  # counts because these tests name it; without the setting the socket
  # address decides, and every test would share one bucket.
  setup do
    Application.put_env(:texttile, :client_ip_header, "x-forwarded-for")
    Texttile.Comments.RateLimiter.reset()

    on_exit(fn ->
      Application.delete_env(:texttile, :client_ip_header)
      Texttile.Comments.RateLimiter.reset()
    end)

    :ok
  end

  defp fresh_ip, do: "10.0.#{System.unique_integer([:positive])}.1"

  defp form_token(article, age \\ 10) do
    Phoenix.Token.sign(
      TexttileWeb.Endpoint,
      "comment form",
      {article.id, System.system_time(:second) - age}
    )
  end

  defp send_comment(conn, article, extra \\ %{}) do
    params = @form |> Map.put("t", form_token(article)) |> Map.merge(extra)

    conn
    |> put_req_header("x-forwarded-for", Map.get(extra, "ip", fresh_ip()))
    |> post(~p"/comments/#{article.id}", Map.delete(params, "ip"))
  end

  describe "the comments block on a text" do
    test "shows confirmed comments to everybody, oldest first", %{conn: conn} do
      article = published_post()
      first = send_and_confirm(article, "First words", "one@example.org")
      second = send_and_confirm(article, "Later words", "two@example.org")

      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      assert html =~ "2 comments"
      assert html =~ ~s(id="comment-#{first.id}")
      assert html =~ ~s(id="comment-#{second.id}")
      {first_at, _} = :binary.match(html, "First words")
      {second_at, _} = :binary.match(html, "Later words")
      assert first_at < second_at
    end

    test "an empty block says so and still offers the form", %{conn: conn} do
      article = published_post()
      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      assert html =~ "Nobody has said anything yet."
      assert html =~ ~s(id="comment-form")
      assert html =~ "Post a comment"
    end

    test "a text without comments allowed carries no block", %{conn: conn} do
      article = published_post()
      {:ok, article} = Articles.update_settings(article, %{allow_comments: false})

      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      refute html =~ ~s(id="comments")
      refute html =~ ~s(id="comment-form")
    end

    test "never shows an email address", %{conn: conn} do
      article = published_post()
      send_and_confirm(article, "Words", "secret@example.org")

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ "secret@example.org"
    end
  end

  describe "posting a comment" do
    test "stores it, and the poster sees it waiting while nobody else does", %{conn: conn} do
      article = published_post()

      conn = send_comment(conn, article)
      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"

      html = conn |> recycle() |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "Grandma Christel"
      assert html =~ "waiting for your confirmation"
      assert html =~ "Only you see this."
      assert html =~ "Sent. Follow the link in your mail"

      # another reader sees nothing yet
      other = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
      refute other =~ "Grandma Christel"
      assert other =~ "Nobody has said anything yet."
    end

    test "while confirmation is off it appears for everybody at once", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post()

      conn = send_comment(conn, article)
      assert Phoenix.Flash.get(conn.assigns.flash, :comment_note) =~ "under the text now"

      other = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
      assert other =~ "Grandma Christel"
      refute_email_sent()
    end

    test "a missing field brings the words back instead of losing them", %{conn: conn} do
      article = published_post()

      html =
        conn
        |> send_comment(article, %{"email" => "not-an-address"})
        |> html_response(200)

      assert html =~ ~s(id="comment-error")
      assert html =~ "More of the dog, please."
      assert Comments.for_article(article.id) == []
    end

    test "a filled honeypot drops the comment and says it worked", %{conn: conn} do
      article = published_post()

      conn = send_comment(conn, article, %{"website" => "https://spam.example"})

      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"
      assert Phoenix.Flash.get(conn.assigns.flash, :comment_note) =~ "Sent."
      assert Comments.for_article(article.id) == []
    end

    test "a form sent faster than a person types is dropped", %{conn: conn} do
      Application.put_env(:texttile, :comment_min_age, 3)
      on_exit(fn -> Application.put_env(:texttile, :comment_min_age, 0) end)

      article = published_post()
      conn = send_comment(conn, article, %{"t" => form_token(article, 0)})

      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"
      assert Comments.for_article(article.id) == []
    end

    test "a form without its stamp is dropped", %{conn: conn} do
      article = published_post()
      conn = send_comment(conn, article, %{"t" => "forged"})

      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"
      assert Comments.for_article(article.id) == []
    end

    test "a stamp from another text is dropped", %{conn: conn} do
      article = published_post()
      other = published_post()
      send_comment(conn, article, %{"t" => form_token(other)})

      assert Comments.for_article(article.id) == []
    end

    test "the fourth comment in a minute from one caller is dropped", %{conn: conn} do
      article = published_post()
      ip = fresh_ip()

      for n <- 1..4 do
        build_conn()
        |> send_comment(article, %{"ip" => ip, "email" => "reader#{n}@example.org"})
      end

      assert length(Comments.for_article(article.id)) == 3
      assert conn.state == :unset
    end

    test "a draft, a closed text and a made-up id all answer 404", %{conn: conn} do
      draft = draft_post()
      assert conn |> send_comment(draft) |> html_response(404)

      closed = published_post()
      {:ok, closed} = Articles.update_settings(closed, %{allow_comments: false})
      assert build_conn() |> send_comment(closed) |> html_response(404)

      assert build_conn()
             |> post(~p"/comments/999999", Map.put(@form, "t", "x"))
             |> html_response(404)
    end


    test "a field that is not one line of text is read as nothing", %{conn: conn} do
      article = published_post()

      html = conn |> send_comment(article, %{"body" => ["a", "b"]}) |> html_response(200)

      assert html =~ ~s(id="comment-error")
      assert Comments.for_article(article.id) == []
    end

    test "the stamp survives a form mistake, so the correction is not a bot", %{conn: conn} do
      Application.put_env(:texttile, :comment_min_age, 3)
      on_exit(fn -> Application.put_env(:texttile, :comment_min_age, 0) end)

      article = published_post()
      token = form_token(article, 10)

      # the form comes back with the error, carrying the same stamp
      html =
        conn
        |> send_comment(article, %{"email" => "nope", "t" => token})
        |> html_response(200)

      assert html =~ ~s(id="comment-error")
      assert html =~ token

      # and the corrected comment goes through at once
      conn = build_conn() |> send_comment(article, %{"t" => token})
      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"
      assert [_] = Comments.for_article(article.id)
    end

    test "a spoofed forwarding header does not rotate the bucket", %{conn: _conn} do
      spoofed = published_post()
      trusted = published_post()

      send_four = fn article ->
        for n <- 1..4 do
          build_conn()
          |> put_req_header("x-forwarded-for", "9.9.9.#{n}")
          |> post(
            ~p"/comments/#{article.id}",
            @form
            |> Map.put("t", form_token(article))
            |> Map.put("email", "reader#{n}@example.org")
          )
        end
      end

      # nobody named the header, so the socket address decides and the
      # four spoofed ones share its bucket
      Application.delete_env(:texttile, :client_ip_header)
      send_four.(spoofed)
      assert length(Comments.for_article(spoofed.id)) < 4

      # named by the deployment, the same header is the reader again
      Application.put_env(:texttile, :client_ip_header, "x-forwarded-for")
      send_four.(trusted)
      assert length(Comments.for_article(trusted.id)) == 4
    end
  end

  describe "the confirmation link" do
    test "confirms the address and lands the reader on their comment", %{conn: conn} do
      article = published_post()
      build_conn() |> send_comment(article)
      [comment] = Comments.for_article(article.id)

      conn = get(conn, ~p"/comments/confirm/#{comment.address.token}")
      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"

      html = conn |> recycle() |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "1 comment"
      assert html =~ "Grandma Christel"
      refute html =~ "waiting for your confirmation"
    end

    test "an unknown token is a 404", %{conn: conn} do
      assert conn |> get(~p"/comments/confirm/no-such-token") |> html_response(404)
    end

    test "a link whose text went away lands on the front page", %{conn: conn} do
      article = published_post()
      build_conn() |> send_comment(article)
      [comment] = Comments.for_article(article.id)
      {:ok, _} = Articles.unpublish(Articles.get_article!(article.id), user_fixture())

      conn = get(conn, ~p"/comments/confirm/#{comment.address.token}")
      assert redirected_to(conn) == "/"
    end
  end

  defp send_and_confirm(article, body, email) do
    build_conn() |> send_comment(article, %{"body" => body, "email" => email})
    comment = article.id |> Comments.for_article() |> List.first()
    {:ok, _} = Comments.confirm(comment.address.token)
    comment
  end
end
