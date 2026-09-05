defmodule TexttileWeb.MediaAccessTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.{Accounts, Images, Settings, Uploads}

  @original "/uploads/images/private-abcd.png"
  @rendition "/renditions/320/images/private-abcd.png"
  @cached "/uploads/cache/images__private-abcd-320.png"
  @video "/uploads/videos/private-abcd.web.mp4"
  @paths [
    @original,
    @rendition,
    "/renditions/max/images/private-abcd.png",
    @cached,
    @video,
    "/uploads/site/private-abcd.png",
    "/apple-touch-icon.png"
  ]

  setup do
    path = Uploads.absolute("images/private-abcd.png")
    File.mkdir_p!(Path.dirname(path))
    {:ok, image} = Vix.Vips.Operation.black(1600, 800)
    :ok = Vix.Vips.Image.write_to_file(image, path)
    {:ok, _} = Images.rendition("images/private-abcd.png", 320)

    video = Uploads.absolute("videos/private-abcd.web.mp4")
    File.mkdir_p!(Path.dirname(video))
    File.write!(video, "0123456789")

    icon = Uploads.absolute("site/private-abcd.png")
    File.mkdir_p!(Path.dirname(icon))
    File.cp!(path, icon)
    {:ok, _} = Settings.put(:favicon, "site/private-abcd.png")
    :ok
  end

  describe "a protected blog" do
    setup do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")
      :ok
    end

    test "direct media requests go through the password gate", %{conn: conn} do
      for path <- @paths do
        response = conn |> put_req_header("accept", "image/avif,image/*,*/*;q=0.8") |> get(path)

        assert redirected_to(response) == "/unlock?to=" <> URI.encode_www_form(path)
        assert get_resp_header(response, "cache-control") == ["private, no-store"]
      end
    end

    test "HEAD and video ranges cannot bypass the gate", %{conn: conn} do
      for path <- @paths do
        response = head(conn, path)
        assert response.status == 302
        assert get_resp_header(response, "cache-control") == ["private, no-store"]
      end

      response = conn |> put_req_header("range", "bytes=2-5") |> get(@video)
      assert response.status == 302
      assert get_resp_header(response, "content-range") == []
    end

    test "a locked request does not generate a rendition", %{conn: conn} do
      assert conn |> get("/renditions/640/images/private-abcd.png") |> redirected_to() =~
               "/unlock"

      refute File.exists?(Uploads.absolute("cache/images__private-abcd-640.png"))
    end

    test "the shared password opens every media route without caching", %{conn: conn} do
      conn = post(conn, "/unlock", %{"password" => "sesame", "to" => @original})
      assert redirected_to(conn) == @original

      for path <- @paths do
        response = conn |> recycle() |> get(path)
        assert response(response, 200) != ""
        assert get_resp_header(response, "cache-control") == ["private, no-store"]
      end

      response = conn |> recycle() |> put_req_header("range", "bytes=2-5") |> get(@video)
      assert response(response, 206) == "2345"
      assert get_resp_header(response, "cache-control") == ["private, no-store"]

      response = conn |> recycle() |> get("/uploads/images/missing.png")
      assert response.status == 404
      assert get_resp_header(response, "cache-control") == ["private, no-store"]
    end

    test "an admin can read media until the session is revoked", %{conn: conn} do
      conn = log_in_user(conn, Texttile.AccountsFixtures.user_fixture())

      for path <- @paths do
        response = get(conn, path)
        assert response.status == 200
        assert get_resp_header(response, "cache-control") == ["private, no-store"]
      end

      Accounts.delete_session(get_session(conn, :user_token))

      for path <- @paths do
        assert conn |> get(path) |> redirected_to() =~ "/unlock"
      end
    end

    test "a password change revokes the reader's media access", %{conn: conn} do
      conn = post(conn, "/unlock", %{"password" => "sesame"})
      {:ok, _} = Settings.put(:site_password, "another word")

      for path <- @paths do
        assert conn |> recycle() |> get(path) |> redirected_to() =~ "/unlock"
      end

      conn = conn |> recycle() |> post("/unlock", %{"password" => "another word"})
      assert conn |> recycle() |> get(@original) |> response(200)
    end

    test "removing protection or clearing the password reopens media", %{conn: conn} do
      for {key, value} <- [site_visibility: "public", site_password: ""] do
        {:ok, _} = Settings.put(:site_visibility, "protected")
        {:ok, _} = Settings.put(key, value)

        for path <- @paths do
          response = get(conn, path)
          assert response.status == 200
          assert get_resp_header(response, "cache-control") == ["private, no-cache"]
        end
      end
    end
  end

  test "public media must revalidate before reuse", %{conn: conn} do
    for path <- @paths do
      response = get(conn, path)
      assert response.status == 200
      assert get_resp_header(response, "cache-control") == ["private, no-cache"]
    end
  end

  test "unchanged public uploads revalidate without sending the file again", %{conn: conn} do
    for path <- [@original, @rendition, @cached, @video] do
      response = get(conn, path)
      assert [etag] = get_resp_header(response, "etag")

      response = conn |> put_req_header("if-none-match", etag) |> get(path)
      assert response(response, 304) == ""
      assert get_resp_header(response, "cache-control") == ["private, no-cache"]
    end
  end

  test "a cached public file cannot bypass newly enabled protection", %{conn: conn} do
    for path <- [@original, @rendition, @cached, @video] do
      {:ok, _} = Settings.put(:site_visibility, "public")
      response = get(conn, path)
      assert [etag] = get_resp_header(response, "etag")
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      response = conn |> put_req_header("if-none-match", etag) |> get(path)
      assert response.status == 302
      assert get_resp_header(response, "cache-control") == ["private, no-store"]
      assert get_resp_header(response, "etag") == []
    end
  end

  test "cache revalidation accepts weak, strong, listed, and wildcard tags", %{conn: conn} do
    assert [etag] = conn |> get(@original) |> get_resp_header("etag")

    for tag <- [etag, String.trim_leading(etag, "W/"), ~s("stale", #{etag}), "*"] do
      assert conn |> put_req_header("if-none-match", tag) |> get(@original) |> response(304) == ""
    end

    assert conn |> put_req_header("if-none-match", ~s("stale")) |> get(@original) |> response(200)
  end

  test "the max rendition gets a new validator when the image size changes", %{conn: conn} do
    path = "/renditions/max/images/private-abcd.png"
    response = get(conn, path)
    assert [etag] = get_resp_header(response, "etag")
    {:ok, _} = Settings.put(:image_max_edge, 800)

    updated = conn |> put_req_header("if-none-match", etag) |> get(path)
    assert response(updated, 200) != response(response, 200)
    refute get_resp_header(updated, "etag") == [etag]
  end
end
