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

    on_exit(fn ->
      Application.delete_env(:texttile, :client_ip_header)
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

    test "an empty block is only the form, with nothing said about it", %{conn: conn} do
      article = published_post()
      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      refute html =~ "Nobody has said anything yet."
      # nothing to head either: the section starts at the form
      refute html =~ ~s(id="comment-count")
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
      refute other =~ ~s(id="comment-count")
    end

    test "while confirmation is off it appears for everybody at once", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      # the mail this test refutes is the reader's confirmation link;
      # the mail to the blog is another story, and another test
      {:ok, _} = Settings.put(:notify_on_comment, false)
      article = published_post()

      conn = send_comment(conn, article)
      assert Phoenix.Flash.get(conn.assigns.flash, :comment_note) =~ "under the entry now"

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

    test "a website travels with the comment and carries the name", %{conn: conn} do
      article = published_post()
      {:ok, _} = Settings.put(:comments_require_confirmation, false)

      send_comment(conn, article, %{"website" => "christel-und-der-hund.example"})

      assert [comment] = Comments.for_article(article.id)
      assert comment.website == "https://christel-und-der-hund.example"

      html = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ ~s(href="https://christel-und-der-hund.example")
      assert html =~ ~s(rel="nofollow ugc")
    end

    test "a website nobody can follow brings the words back", %{conn: conn} do
      article = published_post()

      html =
        conn
        |> send_comment(article, %{"website" => "javascript:alert(1)"})
        |> html_response(200)

      assert html =~ ~s(id="comment-error")
      assert html =~ "More of the dog, please."
      assert Comments.for_article(article.id) == []
    end

    test "no website is no link", %{conn: conn} do
      article = published_post()
      {:ok, _} = Settings.put(:comments_require_confirmation, false)

      send_comment(conn, article, %{"website" => ""})

      assert [comment] = Comments.for_article(article.id)
      assert comment.website == nil
    end

    test "a filled honeypot drops the comment and says it worked", %{conn: conn} do
      article = published_post()

      conn = send_comment(conn, article, %{"url" => "https://spam.example"})

      assert redirected_to(conn) == Articles.public_path(article) <> "#comments"
      assert Phoenix.Flash.get(conn.assigns.flash, :comment_note) =~ "Sent."
      assert Comments.for_article(article.id) == []
    end

    test "a form sent faster than a person types is dropped", %{conn: conn} do
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

  # The box under the form. It is not ticked to begin with: the cookie
  # is a convenience nobody needs to read or to write, and a box that
  # is ticked for you is no answer.
  describe "remember me on this device" do
    @writer "_texttile_writer"

    test "the box is not ticked on a browser that never asked", %{conn: conn} do
      article = published_post()

      html = conn |> get(Articles.public_path(article)) |> html_response(200)

      assert html =~ ~s(name="remember")
      refute html =~ ~r/name="remember"[^>]*checked/
    end

    test "the box keeps the three fields, and the next form starts filled", %{conn: conn} do
      article = published_post()

      sent =
        build_conn()
        |> send_comment(article, %{"remember" => "true", "website" => "https://christel.example"})

      assert %{max_age: 15_552_000} = sent.resp_cookies[@writer]

      html =
        build_conn()
        |> Plug.Test.put_req_cookie(@writer, sent.resp_cookies[@writer].value)
        |> get(Articles.public_path(article))
        |> html_response(200)

      assert html =~ ~s(value="Grandma Christel")
      assert html =~ ~s(value="christel@example.org")
      assert html =~ ~s(value="https://christel.example")
      assert html =~ ~r/name="remember"[^>]*checked/
    end

    test "without the box nothing is kept", %{conn: conn} do
      article = published_post()

      sent = build_conn() |> send_comment(article)

      refute Map.has_key?(sent.resp_cookies, @writer)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ ~s(value="Grandma Christel")
    end

    test "unticking it on the next comment takes the cookie away", %{conn: conn} do
      article = published_post()
      sent = build_conn() |> send_comment(article, %{"remember" => "true"})

      again =
        build_conn()
        |> Plug.Test.put_req_cookie(@writer, sent.resp_cookies[@writer].value)
        |> send_comment(article, %{"email" => "second@example.org"})

      assert %{max_age: 0} = again.resp_cookies[@writer]
    end

    # A comment that comes back with a mistake keeps the box as it was
    # sent. Without that, correcting one field would send the next
    # comment with the box empty.
    test "a form that comes back with a mistake keeps the box ticked", %{conn: conn} do
      article = published_post()

      html =
        build_conn()
        |> send_comment(article, %{"remember" => "true", "website" => "not a website"})
        |> html_response(200)

      assert html =~ "Check the form and send it again"
      assert html =~ ~r/name="remember"[^>]*checked/
    end

    test "correcting a mistake does not drop what was already kept", %{conn: conn} do
      article = published_post()
      sent = build_conn() |> send_comment(article, %{"remember" => "true"})
      kept = sent.resp_cookies[@writer].value

      # the same browser, one field mistyped, and the box still ticked
      # because the form came back with it ticked
      again =
        build_conn()
        |> Plug.Test.put_req_cookie(@writer, kept)
        |> send_comment(article, %{"remember" => "true", "email" => "second@example.org"})

      refute match?(%{max_age: 0}, again.resp_cookies[@writer])
    end

    # An account answers for the name and the address, so there is
    # nothing to remember and no box to tick.
    test "somebody signed in is offered no box", %{conn: conn} do
      article = published_post()
      user = user_fixture()

      html =
        conn |> log_in_user(user) |> get(Articles.public_path(article)) |> html_response(200)

      refute html =~ ~s(name="remember")
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

  describe "what an admin did to a comment" do
    test "a released comment stands under the text for everybody", %{conn: conn} do
      article = published_post()
      build_conn() |> send_comment(article)
      [comment] = Comments.for_article(article.id)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ "More of the dog"

      {:ok, _} = Comments.release_comment(comment.id)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "More of the dog"
      assert html =~ "1 comment"
    end

    test "an edited comment reaches readers with the new words", %{conn: conn} do
      article = published_post()
      comment = send_and_confirm(article, "The first words", "one@example.org")

      {:ok, _} = Comments.edit_comment(comment.id, "The words the admin left")

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "The words the admin left"
      refute html =~ "The first words"
    end

    test "a deleted comment is gone from the text while the trash holds it", %{conn: conn} do
      article = published_post()
      comment = send_and_confirm(article, "Words that go", "one@example.org")
      kept = send_and_confirm(article, "Words that stay", "two@example.org")

      {:ok, _} = Comments.delete_comment(comment)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ "Words that go"
      assert html =~ "Words that stay"
      assert html =~ "1 comment"

      # and it comes back exactly where it stood
      {:ok, _} = Comments.restore_comment(comment.id)
      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      assert html =~ "Words that go"
      assert html =~ "2 comments"
      assert Comments.count_for(article.id) == 2
      assert kept.id
    end

    test "the reader who wrote a deleted comment does not see it either", %{conn: conn} do
      article = published_post()
      conn = send_comment(conn, article)
      [comment] = Comments.for_article(article.id)
      {:ok, _} = Comments.delete_comment(comment)

      html = conn |> get(Articles.public_path(article)) |> html_response(200)
      refute html =~ "More of the dog"
    end
  end

  defp send_and_confirm(article, body, email) do
    build_conn() |> send_comment(article, %{"body" => body, "email" => email})
    comment = article.id |> Comments.for_article() |> List.first()
    {:ok, _} = Comments.confirm(comment.address.token)
    comment
  end
end
