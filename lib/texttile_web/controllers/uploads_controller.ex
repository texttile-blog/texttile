defmodule TexttileWeb.UploadsController do
  @moduledoc """
  Serves the files below the uploads root. Stored names carry a random
  tag, so a file may be cached hard: a changed logo is a new name.
  """
  use TexttileWeb, :controller

  alias Texttile.Uploads

  @types %{
    ".svg" => "image/svg+xml",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".webp" => "image/webp",
    ".gif" => "image/gif"
  }

  def show(conn, %{"path" => parts}) do
    root = Path.expand(Uploads.root())
    path = Path.expand(Path.join([root | parts]))
    type = @types[path |> Path.extname() |> String.downcase()]

    if (String.starts_with?(path, root <> "/") and type) && File.regular?(path) do
      # The CSP keeps an uploaded SVG from running script on this
      # origin when somebody opens it directly.
      conn
      |> put_resp_content_type(type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'none'; style-src 'unsafe-inline'"
      )
      |> send_file(200, path)
    else
      send_resp(conn, 404, "not found")
    end
  end
end
