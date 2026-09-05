defmodule TexttileWeb.SiteMetadataTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.{Articles, Settings}

  test "an entry describes its published text and names its canonical address", %{conn: conn} do
    article =
      published_post(
        title: "Harbor mornings",
        body: "# Harbor\n\nFog over the **pier**. Read [our notes](/notes).",
        slug: "harbor",
        publish_date: ~D[2026-03-01]
      )

    html = conn |> get(Articles.public_path(article) <> "?from=mail") |> html_response(200)
    description = "Fog over the pier. Read our notes."
    url = TexttileWeb.Endpoint.url() <> Articles.public_path(article)

    assert attribute(html, "meta[name=description]", "content") == [description]
    assert attribute(html, "meta[property='og:description']", "content") == [description]
    assert attribute(html, "meta[property='og:title']", "content") == ["Harbor mornings"]
    assert attribute(html, "link[rel=canonical]", "href") == [url]
    assert attribute(html, "meta[property='og:url']", "content") == [url]
  end

  test "metadata keeps the live version when an admin sees the working copy", %{conn: conn} do
    user = user_fixture()
    article = published_post(user: user, title: "Published title", body: "Published description.")

    {:ok, article} =
      Articles.update_text(article, %{title: "Working title", body: "Private changes."})

    for session <- [conn, log_in_user(conn, user)] do
      html = session |> get(Articles.public_path(article)) |> html_response(200)
      assert attribute(html, "meta[name=description]", "content") == ["Published description."]
      assert attribute(html, "meta[property='og:title']", "content") == ["Published title"]
    end

    {:ok, article} = Articles.publish_changes(article, user)
    html = conn |> get(Articles.public_path(article)) |> html_response(200)
    assert attribute(html, "meta[name=description]", "content") == ["Private changes."]
  end

  test "a page used as the front page has one canonical address", %{conn: conn} do
    article = published_page(slug: "about", body: "About our travels.")
    {:ok, _} = Settings.put(:front_page, "page:#{article.id}")

    for path <- ["/", "/about"] do
      html = conn |> get(path) |> html_response(200)
      assert attribute(html, "link[rel=canonical]", "href") == [TexttileWeb.Endpoint.url() <> "/"]
      assert attribute(html, "meta[name=description]", "content") == ["About our travels."]
    end
  end

  test "empty entry previews and the list use the site description", %{conn: conn} do
    {:ok, _} = Settings.put(:site_description, "Our travel journal")
    article = published_page(body: "# A heading\n\n![A photograph](/uploads/images/picture.jpg)")

    for path <- [Articles.public_path(article), "/blog"] do
      html = conn |> get(path) |> html_response(200)
      assert attribute(html, "meta[name=description]", "content") == ["Our travel journal"]

      assert attribute(html, "meta[property='og:description']", "content") == [
               "Our travel journal"
             ]
    end
  end

  test "drafts and scheduled entries have no public link metadata", %{conn: conn} do
    user = user_fixture()

    for article <- [draft_post(user: user), scheduled_post(user: user)] do
      path = Articles.public_path(article) || "/preview/#{article.id}"
      assert conn |> get(path) |> response(404)
      html = conn |> log_in_user(user) |> get(path) |> html_response(200)

      assert attribute(html, "link[rel=canonical]", "href") == []
      assert attribute(html, "meta[property='og:title']", "content") == []
      assert attribute(html, "meta[property='og:image']", "content") == []
      assert attribute(html, "meta[name=robots]", "content") == ["noindex, nofollow"]
    end
  end

  test "the password gate reveals no entry metadata", %{conn: conn} do
    article = published_post(body: "Private journal.")
    {:ok, _} = Settings.put(:site_visibility, "protected")
    {:ok, _} = Settings.put(:site_password, "sesame")
    gate = conn |> get(Articles.public_path(article)) |> redirected_to()
    html = conn |> get(gate) |> html_response(200)

    refute html =~ "Private journal."
    assert attribute(html, "link[rel=canonical]", "href") == []
    assert attribute(html, "meta[property='og:image']", "content") == []
  end

  test "descriptions escape quotes without changing the stored text", %{conn: conn} do
    body = ~s|A "quiet" harbor & a calm sea.|
    article = published_post(body: body)
    html = conn |> get(Articles.public_path(article)) |> html_response(200)

    assert attribute(html, "meta[name=description]", "content") == [body]
    assert Articles.get_article!(article.id).body == body
    assert html =~ "A &quot;quiet&quot; harbor &amp; a calm sea."
  end

  defp attribute(html, selector, name) do
    html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end
end
