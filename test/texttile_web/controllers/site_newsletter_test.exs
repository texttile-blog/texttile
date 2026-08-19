defmodule TexttileWeb.SiteNewsletterTest do
  use TexttileWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import Texttile.ArticlesFixtures

  alias Texttile.Newsletter
  alias Texttile.Settings

  # Every test posts from its own address, so the shared rate limiter
  # never counts one test's requests against another's.
  setup do
    Application.put_env(:texttile, :client_ip_header, "x-forwarded-for")

    on_exit(fn ->
      Application.delete_env(:texttile, :client_ip_header)
    end)

    :ok
  end

  defp fresh_ip, do: "10.1.#{System.unique_integer([:positive])}.1"

  defp form_token(age \\ 10) do
    Phoenix.Token.sign(
      TexttileWeb.Endpoint,
      "newsletter form",
      System.system_time(:second) - age
    )
  end

  defp send_join(conn, extra \\ %{}) do
    params = Map.merge(%{"email" => "reader@example.org", "t" => form_token()}, extra)

    conn
    |> put_req_header("x-forwarded-for", Map.get(extra, "ip", fresh_ip()))
    |> post(~p"/newsletter", Map.delete(params, "ip"))
  end

  describe "the Subscribe section" do
    test "is the last section of every reader page", %{conn: conn} do
      article = published_post(tags: "harbour")

      for path <- ["/blog", Texttile.Articles.public_path(article), "/tags/harbour"] do
        html = conn |> get(path) |> html_response(200)
        assert html =~ ~s(id="subscribe")
        assert html =~ ~s(id="newsletter-form")
        assert html =~ "You get an email when a new entry goes out"
      end
    end
  end

  describe "joining" do
    test "stores the address and mails the link", %{conn: conn} do
      conn = send_join(conn)
      html = html_response(conn, 200)

      assert html =~ "reader@example.org"
      assert [subscriber] = Newsletter.list()
      refute Newsletter.Subscriber.confirmed?(subscriber)
      assert_email_sent(text_body: ~r"/newsletter/confirm/#{subscriber.token}")
    end

    test "an address that is not one gets the form back with a word", %{conn: conn} do
      html = conn |> send_join(%{"email" => "nope"}) |> html_response(200)

      assert html =~ ~s(id="newsletter-error")
      assert Newsletter.list() == []
    end

    test "a filled honeypot is dropped and told it worked", %{conn: conn} do
      html =
        conn
        |> send_join(%{"url" => "https://spam.example"})
        |> html_response(200)

      refute html =~ ~s(id="newsletter-error")
      assert Newsletter.list() == []
      refute_email_sent()
    end

    test "the fourth request in a minute from one caller is dropped", %{conn: _conn} do
      ip = fresh_ip()

      answers =
        for n <- 1..4 do
          build_conn() |> send_join(%{"ip" => ip, "email" => "reader#{n}@example.org"})
        end

      assert length(Newsletter.list()) == 3

      # the dropped one is told the same thing as the three that got
      # through, so a caller learns nothing about the limit
      assert List.last(answers) |> html_response(200) =~ "Now check your mail."
    end
  end

  describe "the confirmation link" do
    test "puts the address on the list and says so", %{conn: conn} do
      build_conn() |> send_join()
      [subscriber] = Newsletter.list()

      html = conn |> get(~p"/newsletter/confirm/#{subscriber.token}") |> html_response(200)

      assert html =~ "on the list"
      assert Newsletter.Subscriber.confirmed?(Newsletter.by_token(subscriber.token))
    end

    test "an unknown token is a 404", %{conn: conn} do
      assert conn |> get(~p"/newsletter/confirm/no-such-token") |> html_response(404)
    end

    test "works while the blog is locked", %{conn: conn} do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      build_conn() |> get(~p"/unlock") |> html_response(200)
      {:ok, subscriber} = Newsletter.join("reader@example.org", confirm_url: &to_string/1)

      html = conn |> get(~p"/newsletter/confirm/#{subscriber.token}") |> html_response(200)
      assert html =~ "on the list"
    end
  end

  describe "the way off the list" do
    test "the link asks once, the button does it", %{conn: conn} do
      {:ok, subscriber} = Newsletter.add("reader@example.org")

      html = conn |> get(~p"/newsletter/unsubscribe/#{subscriber.token}") |> html_response(200)
      assert html =~ "reader@example.org"
      assert html =~ ~s(id="unsubscribe")
      assert Newsletter.list() != []

      html =
        build_conn()
        |> post(~p"/newsletter/unsubscribe/#{subscriber.token}")
        |> html_response(200)

      assert html =~ "off the list"
      assert Newsletter.list() == []
    end

    test "a spent link still answers off the list", %{conn: conn} do
      {:ok, subscriber} = Newsletter.add("reader@example.org")
      :ok = Newsletter.unsubscribe(subscriber.token)

      html = conn |> get(~p"/newsletter/unsubscribe/#{subscriber.token}") |> html_response(200)
      assert html =~ "off the list"

      html =
        build_conn()
        |> post(~p"/newsletter/unsubscribe/#{subscriber.token}")
        |> html_response(200)

      assert html =~ "off the list"
    end
  end
end
