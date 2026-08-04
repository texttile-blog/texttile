defmodule TexttileWeb.UploadsControllerTest do
  use TexttileWeb.ConnCase, async: false

  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())

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

  test "a missing file is a plain 404", %{conn: conn} do
    assert conn |> get(~p"/uploads/site/never-was.png") |> response(404)
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

      conn = get(conn, "/desk/renditions/320/images/pier-abcd.png")
      assert response(conn, 200)
      assert response_content_type(conn, :png) =~ "image/png"

      {:ok, image} =
        Vix.Vips.Image.new_from_file(Uploads.absolute("cache/images__pier-abcd-320.png"))

      assert Vix.Vips.Image.width(image) == 320
    end

    test "an edge outside the fixed list is a 404", %{conn: conn} do
      store_image("images/pier-efgh.png", 1600, 800)
      assert conn |> get("/desk/renditions/9999/images/pier-efgh.png") |> response(404)
    end

    test "signed out, renditions redirect to sign-in" do
      conn = get(build_conn(), "/desk/renditions/320/images/pier-abcd.png")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
