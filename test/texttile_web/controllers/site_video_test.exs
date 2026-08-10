defmodule TexttileWeb.SiteVideoTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos
  alias TexttileWeb.SiteHTML

  setup do
    user = user_fixture()
    {:ok, article} = Articles.create_draft(user)
    %{article: article, user: user}
  end

  defp stored_video(name \\ "Harbour.mov") do
    {:ok, relative} = Uploads.put_body_video(video_file(320, 240), name)
    relative
  end

  defp html(body) do
    %{body: body} |> SiteHTML.body_html() |> Phoenix.HTML.safe_to_string()
  end

  describe "a video in the words" do
    test "plays where it stands, and loads nothing until the reader asks" do
      relative = stored_video()
      {:ok, video} = Videos.convert(Videos.ensure(relative))

      rendered = html("Look:\n\n![Harbour](/uploads/#{relative})")

      assert rendered =~ "<video"
      assert rendered =~ ~s(controls)
      assert rendered =~ ~s(preload="none")
      assert rendered =~ ~s(playsinline)
      assert rendered =~ ~s(src="/uploads/#{video.mp4_path}")
      assert rendered =~ ~s(poster="/renditions/1320/#{video.poster_path}")
      assert rendered =~ ~s(width="320")
      refute rendered =~ "<img"
    end

    test "while it is still converting, the file stands there as a link" do
      relative = stored_video()
      Videos.ensure(relative)

      rendered = html("![Harbour](/uploads/#{relative})")

      refute rendered =~ "<video"
      assert rendered =~ ~s(href="/uploads/#{relative}")
      assert rendered =~ "Harbour"
    end

    test "pictures are untouched by all of this" do
      rendered = html("![A pier](/uploads/images/pier-1234.jpg)")

      assert rendered =~ ~s(<img)
      assert rendered =~ ~s(src="/renditions/1320/images/pier-1234.jpg")
      refute rendered =~ "<video"
    end
  end

  describe "the lightbox shell" do
    test "stands where a picture can open it", %{article: article} do
      article = %{article | body: "![A pier](/uploads/images/pier-1234.jpg)"}

      assert SiteHTML.pictures?(article, [])
    end

    test "stays away from a text whose only file is a video", %{article: article} do
      relative = stored_video()
      {:ok, _} = Videos.convert(Videos.ensure(relative))
      article = %{article | body: "![Harbour](/uploads/#{relative})"}

      # a video plays where it stands; nothing here opens a lightbox
      refute SiteHTML.pictures?(article, [])
    end

    test "stands as soon as the gallery has a tile", %{article: article} do
      assert SiteHTML.pictures?(%{article | body: "Only words."}, [%{id: 1}])
      refute SiteHTML.pictures?(%{article | body: "Only words."}, [])
    end

    test "ignores an upload that is still on its way", %{article: article} do
      article = %{article | body: "![Uploading pier.jpg…]()"}

      refute SiteHTML.pictures?(article, [])
    end
  end

  describe "a video in the gallery" do
    test "the tile is the poster, and it opens the film", %{article: article, user: user} do
      {:ok, article} =
        Articles.update_text(article, %{title: "Harbour", body: "Water and light."})

      {:ok, image} = Gallery.add_file(article, video_file(320, 240), "Harbour.mov")
      {:ok, video} = Videos.convert(Videos.ensure(image.path))
      {:ok, article} = Articles.publish(article, user)

      conn = get(build_conn(), Articles.public_path(article))
      page = html_response(conn, 200)

      # the one tile fills the reading column, so its poster comes at
      # the size a picture in the text comes at
      assert page =~ "/renditions/1320/#{video.poster_path}"
      assert page =~ ~s(data-video="/uploads/#{video.mp4_path}")
    end

    test "a tile that is still converting is not shown yet", %{article: article, user: user} do
      {:ok, article} =
        Articles.update_text(article, %{title: "Harbour", body: "Water and light."})

      {:ok, image} = Gallery.add_file(article, video_file(320, 240), "Harbour.mov")
      Videos.ensure(image.path)
      {:ok, article} = Articles.publish(article, user)

      conn = get(build_conn(), Articles.public_path(article))
      page = html_response(conn, 200)

      refute page =~ image.path
    end
  end
end
