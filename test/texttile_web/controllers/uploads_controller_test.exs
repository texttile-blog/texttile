defmodule TexttileWeb.UploadsControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Uploads

  setup do
    path = Uploads.absolute("site/logo-abcd.svg")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "<svg xmlns='http://www.w3.org/2000/svg'/>")
    :ok
  end

  test "serves a stored file with its type and long caching", %{conn: conn} do
    conn = get(conn, ~p"/uploads/site/logo-abcd.svg")

    assert response(conn, 200) =~ "<svg"
    assert response_content_type(conn, :svg) =~ "image/svg+xml"
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "max-age"
  end

  describe "a video file" do
    setup do
      path = Uploads.absolute("videos/clip-abcd.web.mp4")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "0123456789")
      :ok
    end

    test "comes with its type and says that it takes range requests", %{conn: conn} do
      conn = get(conn, ~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 200) == "0123456789"
      assert get_resp_header(conn, "content-type") == ["video/mp4; charset=utf-8"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    end

    test "answers a seek with the piece that was asked for", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=2-5")
        |> get(~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 206) == "2345"
      assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
    end

    test "an open range runs to the end of the file", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=7-")
        |> get(~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 206) == "789"
      assert get_resp_header(conn, "content-range") == ["bytes 7-9/10"]
    end

    test "asking for the last bytes answers the tail", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=-3")
        |> get(~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 206) == "789"
      assert get_resp_header(conn, "content-range") == ["bytes 7-9/10"]
    end

    test "a range nobody can read is answered whole", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=abc")
        |> get(~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 200) == "0123456789"
    end

    test "a range behind the end is refused", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=20-30")
        |> get(~p"/uploads/videos/clip-abcd.web.mp4")

      assert response(conn, 416)
      assert get_resp_header(conn, "content-range") == ["bytes */10"]
    end
  end

  test "a missing file is a plain 404", %{conn: conn} do
    assert conn |> get(~p"/uploads/site/never-was.png") |> response(404)
  end

  # The wildcard matches with nothing behind it, so a crawler that
  # walks up to the bare folder gets a 404 and not a crash.
  test "the bare address of the folder is a 404 too", %{conn: conn} do
    assert conn |> get("/uploads") |> response(404)
    assert conn |> get("/renditions/640") |> response(404)
  end

  test "a path cannot climb out of the uploads root", %{conn: conn} do
    outside = Path.expand(Path.join(Uploads.root(), "../secret.txt"))
    File.write!(outside, "secret")
    on_exit(fn -> File.rm(outside) end)

    conn = get(conn, "/uploads/..%2Fsecret.txt")
    assert response(conn, 404)
  end

  describe "renditions" do
    setup :register_and_log_in_user

    defp store_image(relative, width, height) do
      path = Uploads.absolute(relative)
      File.mkdir_p!(Path.dirname(path))
      {:ok, black} = Vix.Vips.Operation.black(width, height)
      :ok = Vix.Vips.Image.write_to_file(black, path)
    end

    test "answers with a scaled reading of a large original", %{conn: conn} do
      store_image("images/pier-abcd.png", 1600, 800)

      conn = get(conn, "/renditions/320/images/pier-abcd.png")
      assert response(conn, 200)
      assert response_content_type(conn, :png) =~ "image/png"

      {:ok, image} =
        Vix.Vips.Image.new_from_file(Uploads.absolute("cache/images__pier-abcd-320.png"))

      assert Vix.Vips.Image.width(image) == 320
    end

    test "the max edge answers the reader size of the moment", %{conn: conn} do
      store_image("images/pier-full.png", 4000, 2000)

      conn = get(conn, "/renditions/max/images/pier-full.png")

      assert response(conn, 200)
      assert response_content_type(conn, :png) =~ "image/png"

      # its content follows the Images setting, so never cached as immutable
      assert [cache] = get_resp_header(conn, "cache-control")
      refute cache =~ "immutable"
    end

    test "an edge outside the fixed list is a 404", %{conn: conn} do
      store_image("images/pier-efgh.png", 1600, 800)
      assert conn |> get("/renditions/9999/images/pier-efgh.png") |> response(404)
    end

    test "signed out, renditions answer: the public site shows them" do
      store_image("images/pier-ijkl.png", 1600, 800)
      conn = get(build_conn(), "/renditions/320/images/pier-ijkl.png")
      assert response(conn, 200)
    end
  end
end
