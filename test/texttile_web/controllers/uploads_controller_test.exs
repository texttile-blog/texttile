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
end
