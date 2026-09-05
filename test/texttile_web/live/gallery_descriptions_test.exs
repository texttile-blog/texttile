defmodule TexttileWeb.GalleryDescriptionsTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.{Articles, Gallery}

  setup :register_and_log_in_user

  setup %{user: user} do
    article = published_post(user: user)
    file = jpg_fixture()
    on_exit(fn -> File.rm(file) end)
    {:ok, image} = Gallery.add_file(article, file, "IMG_0113.jpg")
    %{article: article, image: image}
  end

  test "either admin can edit a description and both see it", %{
    conn: conn,
    article: article,
    image: image
  } do
    {:ok, writer, _} = live(conn, "/admin/texts/#{article.id}")
    other = build_conn() |> log_in_user(user_fixture())
    {:ok, watcher, _} = live(other, "/admin/texts/#{article.id}")

    render_hook(watcher, "gallery_set_description", %{
      "id" => to_string(image.id),
      "description" => "A gull."
    })

    assert has_element?(writer, "#tile-#{image.id}[data-description='A gull.']")
    assert has_element?(watcher, "#tile-#{image.id}[data-description='A gull.']")

    render_hook(writer, "gallery_set_description", %{
      "id" => to_string(image.id),
      "description" => ""
    })

    assert has_element?(watcher, "#tile-#{image.id}[data-description='']")
    assert Gallery.get!(article.id, image.id).description == ""
  end

  test "reader tiles use descriptions as alt text and lightbox captions", %{
    article: article,
    image: image
  } do
    description = ~s|A "gull" & <water>.|
    {:ok, _} = Gallery.set_description(article.id, image.id, description)
    html = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
    tile = html |> LazyHTML.from_document() |> LazyHTML.query("#gal a")

    assert LazyHTML.attribute(tile, "data-caption") == [description]
    assert tile |> LazyHTML.query("img") |> LazyHTML.attribute("alt") == [description]
    refute html =~ ~s(alt="IMG_0113.jpg")
  end

  test "a tile without a description has an accessible link without a filename caption", %{
    article: article
  } do
    html = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
    tile = html |> LazyHTML.from_document() |> LazyHTML.query("#gal a")

    assert LazyHTML.attribute(tile, "data-caption") == [""]
    assert LazyHTML.attribute(tile, "aria-label") == ["Open image"]
    assert tile |> LazyHTML.query("img") |> LazyHTML.attribute("alt") == [""]
  end

  test "a whitespace-only description keeps the image link accessible", %{
    article: article,
    image: image
  } do
    {:ok, _} = Gallery.set_description(article.id, image.id, "   ")
    html = build_conn() |> get(Articles.public_path(article)) |> html_response(200)
    tile = html |> LazyHTML.from_document() |> LazyHTML.query("#gal a")
    assert LazyHTML.attribute(tile, "aria-label") == ["Open image"]
  end
end
