defmodule TexttileWeb.E2E.VideoFlowTest do
  @moduledoc """
  The whole way of a video: an admin picks one in the editor, ffmpeg
  converts it in the background, the tile wears its poster, and the
  published text plays it.
  """
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

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
      |> assert_has("#tileCount", text: "0 images")
      |> upload("Add images to the gallery", video_file(640, 480))
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
