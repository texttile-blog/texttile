defmodule TexttileWeb.ExportController do
  @moduledoc """
  Hands one entry out as a zip: the bundle `Texttile.Export` writes,
  which is the format IMPORT.md defines and a Hugo page bundle at the
  same time.

  The zip is made for this request and taken away again the moment it
  has gone out. Nothing is kept: an export is a copy, not a state.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Export

  def show(conn, %{"id" => id}) do
    article = Articles.get_article!(id)
    dir = Path.join(System.tmp_dir!(), "export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      case Export.write_zip(article, dir) do
        {:ok, path} ->
          conn
          |> put_resp_content_type("application/zip", nil)
          |> put_resp_header(
            "content-disposition",
            ~s(attachment; filename="#{quotable(Export.zip_name(article))}")
          )
          |> send_file(200, path)

        {:error, reason} ->
          send_resp(conn, 500, reason)
      end
    after
      File.rm_rf(dir)
    end
  end

  defp quotable(name), do: String.replace(name, ~s("), "")
end
