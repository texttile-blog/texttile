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
    serve(conn, safe_relative(parts))
  end

  # The display sizes the desk asks for. A fixed list, so nobody can
  # fill the disk by walking through edge values. "max" is the reader
  # size of the moment (the Images setting); the gallery lightbox
  # shows it.
  @edges ~w(320 max)

  @doc """
  A scaled reading of an upload: the cached rendition, made on the fly
  when it is missing. The editor's thumbnails come from here instead of
  dragging the full original over the wire.
  """
  def rendition(conn, %{"edge" => edge, "path" => parts}) when edge in @edges do
    max_edge = if edge == "max", do: nil, else: String.to_integer(edge)

    with relative when is_binary(relative) <- safe_relative(parts),
         {:ok, scaled} <- Texttile.Images.rendition(relative, max_edge) do
      serve(conn, scaled)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  def rendition(conn, _params), do: send_resp(conn, 404, "not found")

  # A wildcard path stays below the uploads root or answers nothing.
  defp safe_relative(parts) do
    root = Path.expand(Uploads.root())
    path = Path.expand(Path.join([root | parts]))

    if String.starts_with?(path, root <> "/") do
      Path.relative_to(path, root)
    else
      nil
    end
  end

  defp serve(conn, nil), do: send_resp(conn, 404, "not found")

  defp serve(conn, relative) do
    path = Uploads.absolute(relative)
    type = @types[path |> Path.extname() |> String.downcase()]

    if type && File.regular?(path) do
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
