defmodule TexttileWeb.EditorVideoTest do
  @moduledoc "What the desk says about a video while ffmpeg works on it."
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Lock
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos

  setup :register_and_log_in_user

  setup do
    File.rm_rf!(Uploads.root())

    Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Lock.supervisor(), pid)
    end)

    :ok
  end

  defp draft(user, attrs \\ %{title: "Doors", body: "Wooden ones."}) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, attrs)
    article
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
