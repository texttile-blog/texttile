defmodule TexttileWeb.ExportController do
  @moduledoc """
  Hands one entry out as a zip: the bundle `Texttile.Export` writes,
  which is the format IMPORT.md defines and a Hugo page bundle at the
  same time.

  The zip is streamed as it is made, so the first bytes leave at once.
  A proxy in front of the server gives up on an answer that is silent
  too long, and a bundle with a large film takes longer than that to
  read. The exact size goes out first, so the browser shows how far the
  download has come. Nothing is kept: an export is a copy, not a state.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Export

  def show(conn, %{"id" => id}) do
    article = Articles.get_article!(id)

    case Export.zip(article) do
      {:ok, size, zip} ->
        conn =
          conn
          |> put_resp_content_type("application/zip", nil)
          |> put_resp_header("content-length", Integer.to_string(size))
          |> put_resp_header(
            "content-disposition",
            ~s(attachment; filename="#{quotable(Export.zip_name(article))}")
          )
          |> send_chunked(200)

        Enum.reduce_while(zip, conn, fn piece, conn ->
          case chunk(conn, piece) do
            {:ok, conn} -> {:cont, conn}
            # The browser went away; the stream closes its files.
            {:error, _closed} -> {:halt, conn}
          end
        end)

      {:error, :too_large} ->
        send_resp(
          conn,
          413,
          gettext("This entry is larger than 4 GB, more than one zip can hold.")
        )
    end
  end

  # A quote or a line break in the name would end the header early.
  defp quotable(name), do: String.replace(name, ~r/["\x00-\x1f\x7f]/, "")
end
