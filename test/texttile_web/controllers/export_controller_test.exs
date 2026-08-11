defmodule TexttileWeb.ExportControllerTest do
  use TexttileWeb.ConnCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Gallery

  describe "signed in" do
    setup :register_and_log_in_user

    test "answers with the zip of the entry, named after its address", %{conn: conn} do
      article = published_post(%{title: "Beach days", slug: "beach-days"})
      {:ok, _tile} = Gallery.add_file(article, jpg_fixture(), "beach.jpg")

      conn = get(conn, ~p"/admin/texts/#{article}/export")

      assert response_content_type(conn, :zip) =~ "application/zip"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="beach-days.zip")
             ]

      zip = Path.join(System.tmp_dir!(), "answer-#{System.unique_integer([:positive])}.zip")
      File.write!(zip, response(conn, 200))
      on_exit(fn -> File.rm_rf!(zip) end)

      {:ok, files} = :zip.unzip(String.to_charlist(zip), [:memory])
      names = Enum.map(files, fn {name, _} -> List.to_string(name) end)

      assert "beach-days/index.md" in names
      assert "beach-days/gallery/001_beach.jpg" in names
    end

    test "nothing of the export is left on disk", %{conn: conn} do
      article = published_post(%{title: "Beach days", slug: "beach-days"})

      before = System.tmp_dir!() |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "export-"))
      get(conn, ~p"/admin/texts/#{article}/export")

      after_it =
        System.tmp_dir!() |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "export-"))

      assert after_it == before
    end
  end

  test "a stranger is sent to the sign-in", %{conn: conn} do
    article = published_post(%{title: "Beach days", slug: "beach-days"})

    conn = get(conn, ~p"/admin/texts/#{article}/export")

    assert redirected_to(conn) == ~p"/login"
  end
end
