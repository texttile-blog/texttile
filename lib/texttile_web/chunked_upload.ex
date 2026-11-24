defmodule TexttileWeb.ChunkedUpload do
  @moduledoc """
  The intake both upload addresses share when a file travels in
  pieces.

  The platform in front of the server drops a request body once it
  grows past a few megabytes, so a photograph or a film arrives as
  pieces the browser sends one after the other: each a small request
  of its own, stashed under a token the browser made up. When the last
  piece lands, the pieces are welded into one file and handed to the
  caller's action, the same one a whole-file upload has always run.
  An answer, a refusal and a duplicate therefore look exactly as they
  always did.

  A piece that never arrived, or a server that restarted between
  pieces, answers `409` with `restart: true`: the browser starts the
  file over from piece 0, and piece 0 empties the stash first.
  """

  use Gettext, backend: TexttileWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Texttile.Settings
  alias Texttile.Uploads

  # One piece is 1 MiB on the wire; assets/js/chunks.js holds the same
  # number and cuts the file with it. The browser sends the pieces one
  # after the other, so one file never has two pieces in the air.
  @chunk_bytes 1_048_576

  # A piece twice that size is not one of ours; nothing a browser sends
  # honestly grows past a broken piece that kept streaming.
  @piece_max 2 * @chunk_bytes

  # A roof for the piece count, so a token can never ask the server to
  # weld thousands of empty pieces together.
  @max_parts 5_000

  @type finalize :: (Plug.Conn.t(), Path.t(), String.t() -> Plug.Conn.t())

  @doc """
  Takes one piece of an upload and answers `204`, or welds the pieces
  together on the last one and answers whatever `finalize` answers.
  `finalize` receives the conn to answer on (reading the piece moved
  the connection's own read position, so the answer must go out on the
  conn that came back), the welded file's path and the file's name.
  """
  @spec receive(Plug.Conn.t(), map(), finalize) :: Plug.Conn.t()
  def receive(conn, params, finalize) do
    case pieces(params) do
      {:ok, token, index, parts, size, name} ->
        if size <= Settings.max_upload_bytes() do
          piece(conn, token, index, parts, size, name, finalize)
        else
          conn
          |> put_status(413)
          |> json(%{error: gettext("The file is over the upload limit.")})
        end

      :error ->
        conn
        |> put_status(400)
        |> json(%{error: gettext("The upload arrived in pieces that do not fit together.")})
    end
  end

  defp piece(conn, token, index, parts, size, name, finalize) do
    case read_piece(conn) do
      {:ok, body, conn} ->
        case Uploads.store_chunk(token, index, body) do
          :ok ->
            if index == parts - 1 do
              finish(conn, token, parts, size, name, finalize)
            else
              send_resp(conn, 204, "")
            end

          {:error, :restart} ->
            restart(conn)
        end

      {:error, _reason} ->
        restart(conn)
    end
  end

  defp finish(conn, token, parts, size, name, finalize) do
    case Uploads.assemble_chunks(token, parts, size) do
      {:ok, whole} ->
        try do
          finalize.(conn, whole, name)
        after
          Uploads.drop_chunks(token)
        end

      {:error, :restart} ->
        restart(conn)
    end
  end

  defp restart(conn) do
    conn
    |> put_status(409)
    |> json(%{
      error: gettext("A piece of this upload did not arrive; send it again."),
      restart: true
    })
  end

  # The pieces the browser announces: a token it made up, where the
  # piece sits, how many there are, how big the whole file is, and the
  # name it travels under.
  defp pieces(params) do
    with token when is_binary(token) <- params["upload"],
         true <- Uploads.chunk_token?(token),
         {:ok, index} <- int(params["index"]),
         {:ok, parts} <- int(params["parts"]),
         {:ok, size} <- int(params["size"]),
         true <- parts in 1..@max_parts,
         true <- index in 0..(parts - 1),
         true <- size >= 0,
         name when is_binary(name) and name != "" <- params["name"] do
      {:ok, token, index, parts, size, Path.basename(name)}
    else
      _ -> :error
    end
  end

  # The pieces arrive in the query, so the numbers come as text.
  defp int(value) when is_integer(value), do: {:ok, value}

  defp int(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp int(_value), do: :error

  # The piece rides as the bare body of the request, so no parser
  # touches it and nothing reads it before this does. A body longer
  # than a piece answers {:more, ...}, which means it is not a piece
  # the browser we know would send. The conn that comes back carries
  # the adapter's read position and must be the conn that answers.
  defp read_piece(conn) do
    case read_body(conn, length: @piece_max) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, _conn} -> {:error, :too_big}
      {:error, _reason} -> {:error, :transfer}
    end
  end
end
