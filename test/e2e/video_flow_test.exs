defmodule TexttileWeb.E2E.VideoFlowTest do
  @moduledoc """
  The whole way of a video: an admin picks one in the editor, ffmpeg
  converts it in the background, the tile wears its poster, and the
  published text plays it.
  """
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Ecto.Query, only: [from: 2]
  import Texttile.AccountsFixtures
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    Texttile.DataCase.restore_admin_users_afterwards()
    File.rm_rf!(Uploads.root())

    Texttile.Articles.Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Texttile.Articles.Lock.supervisor(), pid)
    end)

    # The queue stays out of the test environment; this test wants the
    # real one, under its own sandbox owner.
    start_supervised!(Texttile.Videos.Queue)

    %{kb: user_fixture(%{username: "kb"})}
  end

  defp draft!(user) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, %{title: "Harbour", body: "Water and light."})
    article
  end

  defp picture_file do
    path = Path.join(System.tmp_dir!(), "tile-#{System.unique_integer([:positive])}.jpg")
    {:ok, black} = Vix.Vips.Operation.black(40, 30)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    path
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end

  defp wait_until(fun, timeout \\ 20_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) > deadline, do: raise("condition never met")
        Process.sleep(100)
        do_wait(fun, deadline)
    end
  end

  test "a picked video becomes a tile, converts, and plays for the reader", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb)

    session =
      conn
      |> sign_in()
      |> visit("/admin/texts/#{article.id}")
      |> assert_has("#tileCount", text: "0 tiles")
      |> upload("Add pictures and videos to the gallery", video_file(640, 480))
      |> assert_has("#tileServer [data-id]", timeout: 30_000)

    [image] = Gallery.list(article.id)
    assert image.path =~ ~r"^videos/"

    # the desk says what is happening while ffmpeg works, and stops
    # saying it once the poster is there
    video =
      wait_until(fn ->
        match?(%{state: "done"}, Videos.get(image.path)) && Videos.get(image.path)
      end)

    session
    |> assert_has("#tile-#{image.id}[data-video]", timeout: 10_000)
    |> refute_has("#tile-#{image.id}.tile-waiting")

    {:ok, article} = Articles.publish(Articles.get_article!(article.id), kb)

    conn
    |> visit(Articles.public_path(article))
    |> assert_has("#gal a[data-video='/uploads/#{video.mp4_path}']")
  end

  test "the desk lightbox never lands on a tile that has nothing to show", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb)
    {:ok, _picture} = Gallery.add_file(article, picture_file(), "Pier.jpg")
    {:ok, waiting} = Gallery.add_file(article, video_file(320, 240), "Harbour.mov")

    # back to where a long conversion keeps a video: no poster, no
    # film, and a tile with nothing to show
    wait_until(fn -> Videos.state(waiting.path) == :done end)

    Texttile.Repo.update_all(from(v in Texttile.Videos.Video, where: v.path == ^waiting.path),
      set: [state: "queued", mp4_path: nil, poster_path: nil]
    )

    assert Videos.state(waiting.path) == :queued

    conn
    |> sign_in()
    |> visit("/admin/texts/#{article.id}")
    |> assert_has("#tile-#{waiting.id}.tile-waiting")
    |> click("#tileServer [data-id]:not(.tile-waiting)")
    |> assert_has("#lbRoot")
    |> assert_has("#lbCount", text: "1 / 1")
    |> press("#lbRoot", "ArrowRight")
    |> assert_has("#lbCount", text: "1 / 1")
    |> refute_has("#lbState", text: "could not be shown")
  end

  test "a video dropped into the words plays where it stands", %{conn: conn, kb: kb} do
    article = draft!(kb)
    {:ok, relative} = Uploads.put_body_video(video_file(640, 480), "Harbour.mov")
    Videos.queue(relative)

    {:ok, article} =
      Articles.update_text(article, %{body: "Look:\n\n![Harbour](/uploads/#{relative})"})

    video =
      wait_until(fn -> match?(%{state: "done"}, Videos.get(relative)) && Videos.get(relative) end)

    {:ok, article} = Articles.publish(article, kb)

    conn
    |> visit(Articles.public_path(article))
    |> assert_has("video.bodyvid[src='/uploads/#{video.mp4_path}']")
  end
end
