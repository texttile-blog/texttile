defmodule TexttileWeb.BackupController do
  @moduledoc """
  The three things a backup client fetches: the manifest of what is
  here, one file, and a copy of the database.

  Read-only, all three. Nothing here writes anything a caller sends,
  and no caller ever names a path: an id from the manifest is resolved
  against the database and the path comes out of the row. A path in
  the address line is the way out of the uploads folder and into
  everything else on the volume.

  Who may ask is settled before any of this runs
  (`TexttileWeb.BackupGate`).
  """
  use TexttileWeb, :controller

  alias Texttile.Backup
  alias Texttile.Uploads

  # A run starts with the manifest and ends with the database, so
  # these two are what the settings screen dates. The files in
  # between are logged like everything else, but writing a settings
  # row per picture would put thousands of writes in the way of a
  # backup.
  plug :note_access when action in [:manifest, :database]

  defp note_access(conn, _opts) do
    Backup.note_access(conn.assigns.backup_ip)
    conn
  end

  @doc """
  Everything this installation holds, so the client can work out what
  it still needs: the database and its size, and every file with its
  path, its size and its SHA-256.

  Written out in pieces as the list is walked. A blog with a hundred
  thousand pictures would otherwise build the whole answer in memory
  before a byte of it leaves.
  """
  def manifest(conn, _params) do
    # The list is made before the 200 goes out. Reading the tree can
    # fail, and a failure after the status line is a truncated body
    # under a 200: the client would then blame the shape of the JSON
    # for something that went wrong on this side.
    files = Backup.files()

    conn
    |> put_resp_content_type("application/json")
    |> send_chunked(200)
    |> write(head())
    |> write_files(files)
    |> write("]}")
  end

  defp head do
    ~s({"generated_at":#{json(DateTime.utc_now() |> DateTime.to_iso8601())},) <>
      ~s("texttile_version":#{json(Texttile.version())},) <>
      ~s("database":#{json(Backup.database())},) <>
      ~s("files":[)
  end

  defp write_files(conn, files) do
    files
    |> Enum.with_index()
    |> Enum.reduce(conn, fn {file, index}, conn ->
      separator = if index == 0, do: "", else: ","

      write(conn, separator <> json(one(file)))
    end)
  end

  defp one(file), do: %{id: file.id, path: file.path, size: file.size, sha256: file.sha256}

  defp json(term), do: Jason.encode!(term)

  # A client that hangs up mid-manifest is nothing to raise about: the
  # rest of the pieces go nowhere, and the connection is done. Every
  # reason is the same reason here, and a socket has many names for
  # it: closed, epipe, econnreset, a timeout, a word from the server
  # under it.
  defp write(conn, piece) do
    case chunk(conn, piece) do
      {:ok, conn} -> conn
      {:error, _the_client_is_gone} -> halt(conn)
    end
  end

  @doc """
  One original, by the id the manifest gave it. Unknown ids and files
  that have left the disk both answer 404; the client takes that in
  its stride and keeps the copy it already has.
  """
  def file(conn, %{"id" => id}) do
    with %{path: relative} <- Backup.file(id),
         path = Uploads.absolute(relative),
         true <- File.regular?(path) do
      conn
      |> as_a_file(Path.basename(relative))
      |> send_file(200, path)
    else
      _gone -> send_resp(conn, 404, "not found")
    end
  end

  @doc """
  A copy of the database, whole and consistent.

  Made fresh for this request and removed the moment it has gone out.
  """
  def database(conn, _params) do
    name = Backup.database().filename

    Backup.copy_database(fn path ->
      conn
      |> as_a_file(name)
      |> send_file(200, path)
    end)
    |> case do
      {:ok, conn} -> conn
      {:error, _reason} -> send_resp(conn, 500, "the database could not be copied")
    end
  end

  # Bytes, not text: no charset, and a name for whatever writes it out.
  defp as_a_file(conn, name) do
    conn
    |> put_resp_content_type("application/octet-stream", nil)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{quotable(name)}"))
  end

  # A quote or a line break in the name would end the header early.
  defp quotable(name), do: String.replace(name, ~r/["\x00-\x1f\x7f]/, "")
end
