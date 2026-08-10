defmodule Texttile.Backup do
  @moduledoc """
  What a backup machine may fetch, and who may fetch it.

  A backup here is pulled, never pushed. The machine that keeps the
  copies holds the credentials; this installation holds none. Whoever
  breaks into the server finds no way to the backups, because there is
  no way from here to them.

  Three things make up an installation: the database, the uploaded
  files, and the renditions the server made of them. The first two are
  backed up. The renditions are not: they are made again from the
  originals the moment a page asks for one, and leaving them out often
  halves what travels.

  Every original carries a SHA-256 in the database (see
  `Texttile.Backup.Fingerprint`), so a manifest is a query and not a
  walk through every byte on the disk.
  """

  import Ecto.Query

  alias Texttile.Backup.Fingerprint
  alias Texttile.Repo
  alias Texttile.Settings
  alias Texttile.Uploads

  @limiter Texttile.Backup.Limiter

  # A first backup of a blog with pictures asks for one file after
  # another, so this is wide: what it has to stop is a caller running
  # at the disk all day, not a client doing its work. Tests set their
  # own, low enough to reach in a test.
  @limiter_per_minute 600

  @doc "The name of the limiter in front of the backup endpoints."
  def limiter, do: @limiter

  @doc "How many times one caller may fetch in a minute."
  def limiter_per_minute do
    Application.get_env(:texttile, :backup_per_minute, @limiter_per_minute)
  end

  ## The switch, the word and the addresses

  @doc "Whether this installation answers a backup client at all."
  def enabled?, do: Settings.get(:backup_enabled)

  @doc "Whether a token has been made yet."
  def token?, do: stored_token() != ""

  @doc """
  Makes a new token, stores its hash and hands the word itself back.

  This is the only moment the word exists here; nothing keeps it, so
  the screen that asks for it has to show it at once. Making a new one
  takes the one before out of service in the same breath.
  """
  def generate_token do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {:ok, _} = Settings.put(:backup_token_hash, hash(token))
    {:ok, token}
  end

  @doc "Forgets the token. Without one, nothing is served."
  def clear_token do
    {:ok, _} = Settings.put(:backup_token_hash, "")
    :ok
  end

  @doc """
  Whether this word is the token.

  The two hashes are compared in constant time. A comparison that
  stops at the first wrong byte tells a caller how far they got, and
  that is enough to find the word one byte at a time.
  """
  def valid_token?(presented) when is_binary(presented) do
    stored = stored_token()

    stored != "" and Plug.Crypto.secure_compare(hash(presented), stored)
  end

  def valid_token?(_other), do: false

  defp stored_token, do: Settings.get(:backup_token_hash)

  defp hash(token), do: :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)

  @doc """
  The addresses allowed to fetch, as they are written in the settings.
  An empty list is the usual case and means: any address, the token
  decides alone.
  """
  def allowed_ips do
    :backup_allowed_ips
    |> Settings.get()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Whether this address may fetch.

  Both sides are read as addresses first, because one address has many
  spellings and the settings screen takes every one of them. A router
  writes `2001:0DB8:0000::0001` where the socket says `2001:db8::1`,
  and an operator who pastes the first would otherwise lock their own
  backup machine out with no word said anywhere.
  """
  def allowed_ip?(ip) do
    case allowed_ips() do
      [] -> true
      allowed -> address(ip) in Enum.map(allowed, &address/1)
    end
  end

  # The address behind a spelling of it, or the text as it stands when
  # it is no address at all. An IPv4 address that arrives wrapped in
  # IPv6, as it does on a socket that listens for both, is the IPv4
  # address it wraps.
  defp address(text) do
    case text |> String.to_charlist() |> :inet.parse_address() do
      {:ok, {0, 0, 0, 0, 0, 0xFFFF, high, low}} ->
        {Bitwise.bsr(high, 8), Bitwise.band(high, 0xFF), Bitwise.bsr(low, 8),
         Bitwise.band(low, 0xFF)}

      {:ok, parsed} ->
        parsed

      {:error, _no_address} ->
        text
    end
  end

  @doc """
  Remembers that a client fetched something just now. The settings
  screen shows it, so the one person who runs this can see at a glance
  whether the backups still run.
  """
  def note_access(ip) do
    {:ok, _} = Settings.put(:backup_last_access_at, DateTime.utc_now() |> DateTime.to_iso8601())
    {:ok, _} = Settings.put(:backup_last_access_ip, ip)
    :ok
  end

  @doc "When a client last fetched something, and from where. Nil until one has."
  def last_access do
    with at when at != "" <- Settings.get(:backup_last_access_at),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      %{at: at, ip: Settings.get(:backup_last_access_ip)}
    else
      _nothing_yet -> nil
    end
  end

  ## The files

  @doc """
  Every file a backup carries, by path, each with its size and hash.

  The disk is walked and the fingerprints are brought up to date with
  what stands there: a file nobody has seen before is hashed, a file
  whose size or write time has changed is hashed again, and a file
  that has left the disk is forgotten. Everything else answers from
  the row it already has, which is what keeps a daily backup from
  reading every byte it holds.
  """
  def files do
    on_disk = scan()
    stored = Map.new(Repo.all(Fingerprint), &{&1.path, &1})

    # Hashing comes first and outside the transaction. SQLite lets one
    # connection write at a time, and the first backup of a blog with
    # ten gigabytes of pictures reads every byte of them. A write
    # transaction held open for that is a blog that cannot save a text
    # while its backup runs.
    hashed =
      on_disk
      |> Enum.reject(&current?(Map.get(stored, &1.path), &1))
      |> Enum.flat_map(&with_digest/1)

    vanished = Map.keys(stored) -- Enum.map(on_disk, & &1.path)

    {:ok, _} =
      Repo.transaction(fn ->
        forget(vanished)
        remember(hashed)
      end)

    Repo.all(from f in Fingerprint, order_by: f.path)
  end

  @doc """
  One file by the id a manifest gave it, or nil.

  The id is resolved here and the path comes out of the row. A path
  the caller names is a path the caller chooses, and the way out of
  the uploads root and into the database file lies through one.
  """
  def file(id) when is_integer(id), do: Repo.get(Fingerprint, id)

  def file(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> file(id)
      _not_a_number -> nil
    end
  end

  def file(_other), do: nil

  defp current?(nil, _file), do: false
  defp current?(row, file), do: row.size == file.size and row.mtime == file.mtime

  # In batches, because SQLite takes only so many values in one
  # statement, and one row at a time would be one transaction per
  # picture on a first run.
  @batch 200

  defp remember(files) do
    files
    |> Enum.map(&%{path: &1.path, size: &1.size, mtime: &1.mtime, sha256: &1.sha256})
    |> Enum.chunk_every(@batch)
    |> Enum.each(
      &Repo.insert_all(Fingerprint, &1,
        on_conflict: {:replace, [:size, :mtime, :sha256]},
        conflict_target: :path
      )
    )
  end

  defp forget([]), do: :ok

  defp forget(paths) do
    paths
    |> Enum.chunk_every(@batch)
    |> Enum.each(&Repo.delete_all(from f in Fingerprint, where: f.path in ^&1))
  end

  # The whole tree is stated first and hashed after, so a file may go
  # between the two: deleting an entry takes its pictures at once, and
  # the hashing pass of a first backup runs for minutes. A file that
  # cannot be read when its turn comes is left out of this run instead
  # of ending it. The same answer serves a file this server may not
  # read, which is no more the backup's business.
  defp with_digest(file) do
    case digest(Uploads.absolute(file.path)) do
      nil -> []
      sha256 -> [Map.put(file, :sha256, sha256)]
    end
  end

  # Read in pieces, so a film never has to fit in memory beside itself.
  @chunk 262_144

  defp digest(path) do
    path
    |> File.stream!(@chunk)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  rescue
    File.Error -> nil
  end

  ## The walk

  defp scan, do: Enum.flat_map(Uploads.kept_dirs(), &walk/1)

  defp walk(relative) do
    case File.ls(Uploads.absolute(relative)) do
      {:ok, names} ->
        names
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.flat_map(&look(Path.join(relative, &1)))

      {:error, _no_such_folder} ->
        []
    end
  end

  # A file may go between the listing and the asking, and a folder that
  # holds nothing of ours holds nothing to report.
  defp look(relative) do
    case File.stat(Uploads.absolute(relative), time: :posix) do
      {:ok, %File.Stat{type: :directory}} ->
        walk(relative)

      {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
        [%{path: relative, size: size, mtime: mtime}]

      _gone_or_strange ->
        []
    end
  end

  ## The database

  @doc """
  The name of the database file and how big it is right now.

  The size is the file on disk, for the client to show. What actually
  travels is the copy, which is written afresh and comes out a little
  smaller.
  """
  def database do
    path = database_path()

    %{filename: Path.basename(path), size: File.stat!(path).size}
  end

  @doc """
  Writes a consistent copy of the database, hands the path to `fun`,
  and removes the copy afterwards, whatever `fun` did. Answers
  `{:ok, whatever fun answered}`.

  The live file is never served. SQLite writes as it is read, so a
  copy taken byte by byte while somebody saves a text is a file that
  opens nowhere. `VACUUM INTO` writes a whole database out of one
  read transaction, which is the same thing `make db-pull` does.

  The copy is written beside the database, so it lands on the volume
  that was sized for it, and under a name of its own, so two clients
  fetching at once never meet in one file.
  """
  def copy_database(fun) when is_function(fun, 1) do
    source = database_path()
    target = Path.join(Path.dirname(source), ".backup-#{unique()}.db")

    try do
      case vacuum_into(source, target) do
        :ok -> {:ok, fun.(target)}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(target)
      File.rm(target <> "-wal")
      File.rm(target <> "-shm")
    end
  end

  defp database_path, do: Repo.config()[:database]

  defp unique, do: 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  # A connection of its own: VACUUM refuses to run inside a
  # transaction, and the pooled ones are in one often enough (a test
  # always is).
  defp vacuum_into(source, target) do
    case Exqlite.Sqlite3.open(source, mode: [:readwrite]) do
      {:ok, conn} ->
        try do
          Exqlite.Sqlite3.execute(conn, "VACUUM INTO '#{escape(target)}'")
        after
          Exqlite.Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp escape(path), do: String.replace(path, "'", "''")
end
