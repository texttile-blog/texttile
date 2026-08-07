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
    ".gif" => "image/gif",
    ".mp4" => "video/mp4",
    ".m4v" => "video/x-m4v",
    ".mov" => "video/quicktime",
    ".webm" => "video/webm",
    ".avi" => "video/x-msvideo",
    ".mkv" => "video/x-matroska"
  }

  def show(conn, %{"path" => parts}) do
    serve(conn, safe_relative(parts))
  end

  # The display sizes the site asks for. A fixed list, so nobody can
  # fill the disk by walking through edge values: 320 for the small
  # tiles, 640 for the reader's cards and gallery squares, 1320 for
  # the pictures inside a text, and "max" - the reader size of the
  # moment (the Images setting) - for the lightboxes.
  @edges ~w(320 640 1320 max)

  @immutable "public, max-age=31536000, immutable"

  @doc """
  A scaled reading of an upload: the cached rendition, made on the fly
  when it is missing. The editor's thumbnails come from here instead of
  dragging the full original over the wire.
  """
  def rendition(conn, %{"edge" => edge, "path" => parts}) when edge in @edges do
    max_edge = if edge == "max", do: nil, else: String.to_integer(edge)

    # A numbered edge of an immutably named original never changes;
    # "max" follows the Images setting, so it may only be cached briefly.
    cache = if edge == "max", do: "public, max-age=3600", else: @immutable

    with relative when is_binary(relative) <- safe_relative(parts),
         {:ok, scaled} <- Texttile.Images.rendition(relative, max_edge) do
      serve(conn, scaled, cache)
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

  defp serve(conn, relative, cache \\ @immutable)

  defp serve(conn, nil, _cache), do: send_resp(conn, 404, "not found")

  defp serve(conn, relative, cache) do
    path = Uploads.absolute(relative)
    type = @types[path |> Path.extname() |> String.downcase()]

    if type && File.regular?(path) do
      # The CSP keeps an uploaded SVG from running script on this
      # origin when somebody opens it directly.
      conn
      |> put_resp_content_type(type)
      |> put_resp_header("cache-control", cache)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'none'; style-src 'unsafe-inline'"
      )
      |> put_resp_header("accept-ranges", "bytes")
      |> send_part(path, File.stat!(path).size)
    else
      send_resp(conn, 404, "not found")
    end
  end

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
