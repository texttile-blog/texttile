defmodule TexttileWeb.EditorVideoTest do
  @moduledoc "What the admin area says about a video while ffmpeg works."
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos

  setup :register_and_log_in_user

  defp draft(user, attrs \\ %{title: "Doors", body: "Wooden ones."}) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, attrs)
    article
  end

  # What the writing surface gets to draw its inline previews with, out
  # of the rendered attribute; HEEx escapes the quotes of the JSON.
  defp posters_of(html) do
    [_whole, raw] = Regex.run(~r/data-posters="([^"]*)"/, html)

    raw |> String.replace("&quot;", "\"") |> Jason.decode!()
  end

  defp body_video(article) do
    {:ok, relative} = Uploads.put_body_video(video_file(320, 240), "Harbour.mov")
    Videos.ensure(relative)

    {:ok, article} =
      Articles.update_text(article, %{body: "Look:\n\n![Harbour](/uploads/#{relative})"})

    {article, relative}
  end

  describe "a video in the text" do
    test "says that it is being converted", %{conn: conn, user: user} do
      {article, _relative} = body_video(draft(user))

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      assert has_element?(view, "#inlineImgs", ".mov")
      assert has_element?(view, "#inlineImgs", "waiting to be converted")
    end

    test "says what went wrong when ffmpeg gave up", %{conn: conn, user: user} do
      {article, relative} = body_video(draft(user))
      Videos.give_up(relative, "moov atom not found")

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      assert has_element?(view, "#inlineImgs", "moov atom not found")
    end

    test "shows the poster once the conversion is through", %{conn: conn, user: user} do
      {article, relative} = body_video(draft(user))
      {:ok, video} = Videos.convert(Videos.get(relative))

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      assert render(view) =~ video.poster_path
      refute has_element?(view, "#inlineImgs", "waiting to be converted")
    end

    test "a conversion that finishes elsewhere reaches the open editor", %{
      conn: conn,
      user: user
    } do
      {article, relative} = body_video(draft(user))

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      assert has_element?(view, "#inlineImgs", "waiting to be converted")

      {:ok, video} = Videos.convert(Videos.get(relative))

      assert render(view) =~ video.poster_path
    end
  end

  describe "the poster in the writing surface" do
    test "the editor carries the poster of every converted video", %{conn: conn, user: user} do
      {article, relative} = body_video(draft(user))
      {:ok, video} = Videos.convert(Videos.get(relative))

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      posters = posters_of(render(view))

      # the thumbnail's poster, the poster the lightbox stands behind
      # the film, and the film itself
      assert posters == %{
               "/uploads/#{relative}" => %{
                 "poster" => "/renditions/320/#{video.poster_path}",
                 "full" => "/renditions/max/#{video.poster_path}",
                 "film" => "/uploads/#{video.mp4_path}"
               }
             }
    end

    test "a video that is not converted carries none", %{conn: conn, user: user} do
      {article, _relative} = body_video(draft(user))

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      assert posters_of(render(view)) == %{}
    end

    test "a conversion that finishes hands the poster to the open editor", %{
      conn: conn,
      user: user
    } do
      {article, relative} = body_video(draft(user))
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")

      {:ok, video} = Videos.convert(Videos.get(relative))
      render(view)

      # the conversion says twice where it stands, and only the second
      # word carries a poster
      url = "/uploads/#{relative}"
      assert_push_event(view, "sync_media", %{posters: %{^url => film}})

      assert film == %{
               poster: "/renditions/320/#{video.poster_path}",
               full: "/renditions/max/#{video.poster_path}",
               film: "/uploads/#{video.mp4_path}"
             }
    end
  end

  describe "a video in the gallery" do
    test "the tile waits, and then wears its poster", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, image} = Gallery.add_file(article, video_file(320, 240), "Harbour.mov")

      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      assert has_element?(view, "#tile-#{image.id}.tile-waiting")

      {:ok, video} = Videos.convert(Videos.get(image.path))

      assert render(view) =~ video.poster_path
      assert has_element?(view, "#tile-#{image.id}[data-video]")
    end
  end
end
