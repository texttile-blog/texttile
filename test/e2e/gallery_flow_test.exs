defmodule TexttileWeb.E2E.GalleryFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles
  alias Texttile.Gallery

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    Texttile.DataCase.restore_admin_users_afterwards()

    Texttile.Articles.Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Texttile.Articles.Lock.supervisor(), pid)
    end)

    %{kb: user_fixture(%{username: "kb"})}
  end

  defp draft!(user) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, %{title: "Doors", body: "Wooden ones."})
    article
  end

  # A real JPEG on disk, with a capture date the gallery can read.
  defp jpg!(taken) do
    path = Path.join(System.tmp_dir!(), "e2e-#{System.unique_integer([:positive])}.jpg")
    {:ok, black} = Vix.Vips.Operation.black(40, 20)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        :ok = Vix.Vips.MutableImage.set(mut, "exif-ifd2-DateTimeOriginal", :gchararray, taken)
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  defp seed!(article, name, taken) do
    {:ok, image} = Gallery.add_image(article, jpg!(taken), name)
    image
  end

  describe "uploading" do
    test "a picked file becomes a tile, the count follows", %{conn: conn, kb: kb} do
      article = draft!(kb)

      conn
      |> sign_in()
      |> visit("/edit/texts/#{article.id}")
      |> assert_has("#tileCount", text: "0 images")
      |> upload("Add images to the gallery", jpg!("2024:05:01 12:00:00"))
      |> assert_has("#tileServer [data-id]")
      |> assert_has("#tileCount", text: "1 image")

      assert [%{filename: "e2e-" <> _}] = Gallery.list(article.id)
    end

    test "a photo far past the old 8 MB parser default arrives", %{conn: conn, kb: kb} do
      article = draft!(kb)

      big = Path.join(System.tmp_dir!(), "big-#{System.unique_integer([:positive])}.jpg")
      {:ok, noise} = Vix.Vips.Operation.gaussnoise(4000, 3000, sigma: 40.0)
      {:ok, bands} = Vix.Vips.Operation.bandjoin([noise, noise, noise])
      {:ok, cast} = Vix.Vips.Operation.cast(bands, :VIPS_FORMAT_UCHAR)
      :ok = Vix.Vips.Image.write_to_file(cast, big, Q: 95)
      assert File.stat!(big).size > 9_000_000

      conn
      |> sign_in()
      |> visit("/edit/texts/#{article.id}")
      |> upload("Add images to the gallery", big)
      |> assert_has("#tileServer [data-id]", timeout: 30_000)

      assert [_] = Gallery.list(article.id)
    end

    test "a file past the 50 MB roof fails on the spot, nothing travels", %{conn: conn, kb: kb} do
      article = draft!(kb)

      huge = Path.join(System.tmp_dir!(), "huge-#{System.unique_integer([:positive])}.jpg")
      {:ok, file} = File.open(huge, [:write])
      :ok = :file.pwrite(file, 51 * 1024 * 1024, <<0>>)
      :ok = File.close(file)

      conn
      |> sign_in()
      |> visit("/edit/texts/#{article.id}")
      |> upload("Add images to the gallery", huge)
      |> assert_has("#tileLocal .tile.failed", text: "50 MB")
      |> assert_has("#tileLocal button[data-act=remove]")
      |> refute_has("#tileLocal button[data-act=retry]")

      assert Gallery.list(article.id) == []
    end
  end

  describe "sorting" do
    test "a mouse drag over the tiles writes a new order", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "a.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "b.jpg", "2024:05:01 12:00:00")
      c = seed!(article, "c.jpg", "2024:05:01 14:00:00")

      conn
      |> sign_in()
      |> visit("/edit/texts/#{article.id}")
      |> assert_has("#tileCount", text: "3 images")
      |> drag("#tile-#{c.id}", to: "#tile-#{a.id}")

      wait_until(fn ->
        Enum.map(Gallery.list(article.id), & &1.id) == [c.id, a.id, b.id]
      end)

      # the numbers followed the drop
      conn |> assert_has("#tile-#{c.id} .n", text: "01")
    end
  end

  describe "the lightbox" do
    test "opens on a tap, navigates, edits, and survives background changes",
         %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn =
        conn
        |> sign_in()
        |> visit("/edit/texts/#{article.id}")
        |> assert_has("#tileCount", text: "2 images")
        |> click("#tileServer [data-id='#{a.id}']")
        |> assert_has("#lbRoot")
        |> assert_has("#lbName", text: "pier.jpg")
        |> assert_has("#lbCount", text: "1 / 2")
        |> press("#lbRoot", "ArrowRight")
        |> assert_has("#lbName", text: "gull.jpg")

      # a picture added elsewhere: the count moves, the lightbox stays
      seed!(article, "fog.jpg", "2024:05:01 14:00:00")

      conn
      |> assert_has("#tileCount", text: "3 images")
      |> assert_has("#lbRoot")
      |> assert_has("#lbName", text: "gull.jpg")

      # the date picker resorts the gallery at once
      conn = fill_in(conn, "Date", with: "2024-05-01T15:00")

      wait_until(fn ->
        article.id |> Gallery.list() |> List.last() |> Map.fetch!(:id) == b.id
      end)

      conn
      |> press("#lbRoot", "Escape")
      |> refute_has("#lbRoot")
    end
  end

  describe "delete and the way back" do
    test "the tile leaves at once and undo puts it back", %{conn: conn, kb: kb} do
      article = draft!(kb)
      a = seed!(article, "pier.jpg", "2024:05:01 10:00:00")
      _b = seed!(article, "gull.jpg", "2024:05:01 12:00:00")

      conn
      |> sign_in()
      |> visit("/edit/texts/#{article.id}")
      |> click("#tileServer [data-id='#{a.id}']")
      |> assert_has("#lbRoot")
      |> click_button("Delete image")
      |> assert_has("#undoBar", text: "pier.jpg")
      |> assert_has("#tileCount", text: "1 image")
      |> assert_has("#lbName", text: "gull.jpg")
      |> click_button("Undo")
      |> assert_has("#tileCount", text: "2 images")
      |> assert_has("#tileServer [data-id='#{a.id}']")

      assert Enum.map(Gallery.list(article.id), & &1.filename) == ["pier.jpg", "gull.jpg"]
    end
  end

  defp wait_until(fun, timeout \\ 3000) do
    do_wait(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp do_wait(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) > deadline, do: raise("condition never met")
        Process.sleep(50)
        do_wait(fun, deadline)
    end
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end
end
