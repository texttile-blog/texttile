defmodule TexttileWeb.UploadsController do
  @moduledoc """
  Serves files below the uploads root after the router checks access.
  Public files require revalidation, so later password protection takes effect.
  Protected files must not be stored in browser or shared caches.
  """
  use TexttileWeb, :controller

  alias Texttile.Uploads

  @types %{
    ".svg" => "image/svg+xml",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".webp" => "image/webp",
    ".gif" => "image/gif",
    ".mp4" => "video/mp4",
    ".m4v" => "video/x-m4v",
    ".mov" => "video/quicktime",
    ".webm" => "video/webm",
    ".avi" => "video/x-msvideo",
    ".mkv" => "video/x-matroska"
  }

  def show(conn, %{"path" => parts}) do
    serve(conn, Uploads.under_root(parts))
  end

  # The display sizes the site asks for. A fixed list, so nobody can
  # fill the disk by walking through edge values: 320 for the small
  # tiles, 640 for the reader's cards and gallery squares, 1320 for
  # the pictures inside a text, and "max" - the reader size of the
  # moment (the Images setting) - for the lightboxes.
  @edges ~w(320 640 1320 max)

  @doc """
  A scaled reading of an upload: the cached rendition, made on the fly
  when it is missing. The editor's thumbnails come from here instead of
  dragging the full original over the wire.
  """
  def rendition(conn, %{"edge" => edge, "path" => parts}) when edge in @edges do
    max_edge = if edge == "max", do: nil, else: String.to_integer(edge)

    with relative when is_binary(relative) <- Uploads.under_root(parts),
         {:ok, scaled} <- Texttile.Images.rendition(relative, max_edge) do
      serve(conn, scaled)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  def rendition(conn, _params), do: send_resp(conn, 404, "not found")

  defp serve(conn, nil), do: send_resp(conn, 404, "not found")

  defp serve(conn, relative) do
    path = Uploads.absolute(relative)
    type = @types[path |> Path.extname() |> String.downcase()]

    if type && File.regular?(path) do
      # The CSP keeps an uploaded SVG from running script on this
      # origin when somebody opens it directly.
      conn
      |> put_resp_content_type(type)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'none'; style-src 'unsafe-inline'"
      )
      |> put_resp_header("accept-ranges", "bytes")
      |> send_cached(path, File.stat!(path))
    else
      send_resp(conn, 404, "not found")
    end
  end

  defp send_cached(%{assigns: %{media_guarded: false}} = conn, path, stat) do
    # Include the resolved path: the max rendition changes with the Images setting.
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({path, stat.size, stat.mtime}))
    etag = ~s(W/"#{Base.url_encode64(digest, padding: false)}")
    conn = put_resp_header(conn, "etag", etag)

    matches? =
      conn
      |> get_req_header("if-none-match")
      |> Enum.flat_map(&Plug.Conn.Utils.list/1)
      |> Enum.any?(
        &(&1 == "*" or String.trim_leading(&1, "W/") == String.trim_leading(etag, "W/"))
      )

    if matches?, do: send_resp(conn, 304, ""), else: send_part(conn, path, stat.size)
  end

  defp send_cached(conn, path, stat), do: send_part(conn, path, stat.size)

  # A player asks for the piece it needs, not for the whole film: it
  # seeks by asking for a range of bytes, and some browsers play
  # nothing at all without an answer in kind.
  defp send_part(conn, path, size) do
    case requested_range(conn, size) do
      :whole ->
        send_file(conn, 200, path)

      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :beyond ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  defp requested_range(conn, size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> spec] -> range_from(spec, size)
      _ -> :whole
    end
  end

  # One range, which is what every player asks for. `first-last`,
  # `first-` to the end, and `-count` for the last count bytes.
  defp range_from(spec, size) do
    case String.split(spec, "-", parts: 2) do
      ["", count] -> take_last(count, size)
      [first, ""] -> take_from(first, size)
      [first, last] -> take_between(first, last, size)
      _ -> :whole
    end
  end

  defp take_last(count, size) do
    case Integer.parse(count) do
      # an empty file has no last bytes to give, like it has no others
      {_count, ""} when size == 0 -> :beyond
      {count, ""} when count > 0 -> {:ok, max(size - count, 0), size - 1}
      _ -> :whole
    end
  end

  defp take_from(first, size) do
    case Integer.parse(first) do
      {first, ""} when first < size -> {:ok, first, size - 1}
      {_first, ""} -> :beyond
      _ -> :whole
    end
  end

  defp take_between(first, last, size) do
    with {first, ""} <- Integer.parse(first),
         {last, ""} <- Integer.parse(last),
         true <- first <= last and first < size do
      {:ok, first, min(last, size - 1)}
    else
      false -> :beyond
      _ -> :whole
    end
  end
end
