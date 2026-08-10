defmodule Texttile.Uploads do
  @moduledoc """
  The uploaded files on disk. Everything lives below one root from the
  install config (`UPLOADS_PATH`), so one volume carries it all: the
  same layout on a laptop, in a container and on Fly.

      site/    the logo and the favicon
      images/  the originals of every picture (comes with the editor)
      videos/  the originals of every video, and what ffmpeg made of
               them (see Texttile.Videos)
      cache/   renditions, disposable (see Texttile.Images)
  """

  import Ecto.Query

  alias Texttile.Repo
  alias Texttile.Settings
  alias Texttile.Uploads.Digest

  @doc "The uploads root from the install config."
  def root do
    Application.fetch_env!(:texttile, :uploads_path)
  end

  @doc "The absolute path behind a stored relative one."
  def absolute(relative), do: Path.join(root(), relative)

  @doc """
  The relative path below the root that these pieces name, or nil when
  they climb out of it.

  The names that arrive here are not all the server's own: a wildcard
  route hands over what a caller asked for, and deleting a text hands
  over every reference its body ever held, written by hand. A name that
  climbs out with `..` is no upload of ours, whatever it starts with.

  Takes a relative path or the pieces of one, so the routes and the
  domain read it the same way. This is the one reading.

  The root itself names no file, and neither does nothing at all: the
  wildcard routes match with no piece behind them, so `/uploads` and
  `/renditions/640` arrive here empty and have to answer a 404 like any
  other name that is not a file.
  """
  def under_root(pieces) do
    case List.wrap(pieces) do
      [] ->
        nil

      pieces ->
        root = Path.expand(root())
        path = root |> Path.join(Path.join(pieces)) |> Path.expand()

        if String.starts_with?(path, root <> "/"), do: Path.relative_to(path, root)
    end
  end

  @doc """
  Takes one file below the root. A path that climbs out of it is left
  alone, and a file that is gone already is no error: this is the one
  place a stored file leaves the disk.
  """
  def remove(relative) do
    if path = under_root(relative), do: File.rm(absolute(path))
    :ok
  end

  @doc "Takes a whole folder below the root, with everything in it."
  def remove_dir(relative) do
    if path = under_root(relative), do: File.rm_rf!(absolute(path))
    :ok
  end

  ## The folders of the layout

  @images_dir "images"
  @videos_dir "videos"
  @site_dir "site"
  @cache_dir "cache"

  @doc "Where the originals of the pictures live."
  def images_dir, do: @images_dir

  @doc "Where the originals of the videos live, and what ffmpeg made of them."
  def videos_dir, do: @videos_dir

  @doc "Where the logo and the favicon live."
  def site_dir, do: @site_dir

  @doc "Where the renditions live. Everything in it is disposable."
  def cache_dir, do: @cache_dir

  # The folders of the layout above, in the order the settings screen
  # names them: what came in first, then what the server made of it.
  @report_dirs [@images_dir, @videos_dir, @site_dir, @cache_dir]

  @doc """
  The folders a backup carries: everything that came in, and what
  ffmpeg made of a film, which no page can make again while a reader
  waits. The cache is left out; a rendition is made again the moment
  a page asks for one.
  """
  def kept_dirs, do: @report_dirs -- [@cache_dir]

  @doc """
  What lies below the root, one row per folder: how many files and how
  many bytes. A folder that does not exist yet answers with zeros
  instead of an error, because an empty blog has none of them.

  This walks the tree. It is for the settings screen, which one person
  opens now and then, and not for a page a reader loads.
  """
  def usage do
    Enum.map(@report_dirs, fn dir ->
      {files, bytes} = weigh(absolute(dir))
      %{dir: dir, files: files, bytes: bytes}
    end)
  end

  defp weigh(path) do
    case File.ls(path) do
      {:ok, names} ->
        Enum.reduce(names, {0, 0}, fn name, {files, bytes} ->
          full = Path.join(path, name)

          case File.stat(full) do
            {:ok, %File.Stat{type: :directory}} ->
              {f, b} = weigh(full)
              {files + f, bytes + b}

            {:ok, %File.Stat{size: size}} ->
              {files + 1, bytes + size}

            {:error, _reason} ->
              {files, bytes}
          end
        end)

      {:error, _reason} ->
        {0, 0}
    end
  end

  @doc """
  How many bytes the volume that carries the uploads still has, or nil
  when the system will not say.

  `df` is the one answer every place this runs agrees on: the Debian
  image, a Mac and a Linux laptop. `-P` promises one line per
  filesystem, so the columns can be counted; `-k` promises kilobytes,
  so the number means the same everywhere. It spawns a process, so ask
  it when the screen is opened and not on every keystroke it saves.
  """
  def free_bytes do
    case System.cmd("df", ["-Pk", root()], stderr_to_stdout: true) do
      {out, 0} -> available(out)
      {_out, _code} -> nil
    end
  rescue
    # no df on this system, or a line that does not read as numbers
    _error -> nil
  end

  defp available(out) do
    with [_head, line | _rest] <- String.split(out, "\n", trim: true),
         [_fs, _blocks, _used, avail | _rest] <- String.split(line) do
      String.to_integer(avail) * 1024
    else
      _ -> nil
    end
  end

  @marks [:logo, :favicon]
  @mark_extensions ~w(.svg .png .jpg .jpeg .webp)

  # A mark is shown small everywhere: a logo up to 84 css px wide in the
  # bar, a favicon up to 32 in a browser tab. This covers the widest of
  # them at three times the density, which is as far as screens go, and
  # keeps a multi-megapixel upload from riding along on every page.
  @mark_max_edge 256

  @doc "How large a raster logo or favicon is kept, on the longer edge."
  def mark_max_edge, do: @mark_max_edge

  # An SVG is stored as it came, so this is its only brake.
  @mark_max_svg_bytes 512_000

  @doc """
  Stores an uploaded logo or favicon and remembers it in the settings.
  A raster file is scaled down to #{@mark_max_edge} px on the longer
  edge; an SVG is stored as it came. The stored name carries a random
  tag, so a browser never clings to a stale one; the earlier file goes
  with the swap.
  """
  def put_site_mark(mark, source_path, original_name) when mark in @marks do
    extension = original_name |> Path.extname() |> String.downcase()

    cond do
      extension not in @mark_extensions ->
        {:error, "SVG, PNG, JPG or WebP, please"}

      extension == ".svg" and File.stat!(source_path).size > @mark_max_svg_bytes ->
        {:error, "An SVG mark this big would ride along on every page; 500 KB is plenty"}

      true ->
        tag = random_tag()
        relative = "#{site_dir()}/#{mark}-#{tag}#{extension}"
        destination = absolute(relative)
        File.mkdir_p!(Path.dirname(destination))

        stored =
          if extension == ".svg" do
            File.cp!(source_path, destination)
            :ok
          else
            Texttile.Images.shrink_to(source_path, destination, @mark_max_edge)
          end

        case stored do
          :ok ->
            remove_stored_file(mark)
            {:ok, _} = Settings.put(mark, relative)
            {:ok, _} = Settings.put(:"#{mark}_name", original_name)
            {:ok, relative}

          {:error, _reason} ->
            remove(relative)
            {:error, "The file could not be read as an image"}
        end
    end
  end

  @body_image_extensions ~w(.png .jpg .jpeg .webp .gif)

  @doc """
  Stores an image pasted or dropped into a text's body, below `images/`.
  The original is kept as it came; display sizes are renditions
  (`Texttile.Images`). The stored name keeps the readable base of the
  original plus a random tag, so names never collide and the file may
  be cached hard.

  What the file is made of is remembered with it, so an entry can take
  each picture once (`duplicate/2`).
  """
  def put_body_image(source_path, original_name) do
    store(source_path, original_name,
      directory: images_dir(),
      extensions: @body_image_extensions,
      fallback: "image",
      refusal: "PNG, JPG, WebP or GIF, please",
      remember: true,
      readable: fn path ->
        if readable_image?(path),
          do: :ok,
          else: {:error, "The file could not be read as an image"}
      end
    )
  end

  @doc """
  Stores an uploaded video below `videos/`. The file is kept exactly
  as it came; what a page plays is derived from it later
  (`Texttile.Videos`). Nothing is read here: a video is only opened
  once, by ffmpeg, and a file that turns out to hold no video fails
  there with a reason the editor shows.
  """
  def put_body_video(source_path, original_name) do
    store(source_path, original_name,
      directory: videos_dir(),
      extensions: Texttile.Videos.extensions(),
      fallback: "video",
      refusal: "MP4, MOV, M4V, WebM, AVI or MKV, please"
    )
  end

  # The one way a body file lands on disk: the extension decides
  # whether it may, an optional reading says whether the file is what
  # it claims, and the readable base of the name plus a random tag make
  # the stored name.
  defp store(source_path, original_name, opts) do
    extension = original_name |> Path.extname() |> String.downcase()
    readable = Keyword.get(opts, :readable, fn _path -> :ok end)

    with :ok <- allowed(extension, opts),
         :ok <- readable.(source_path) do
      base =
        case Texttile.Articles.slugify(Path.rootname(original_name)) do
          "" -> opts[:fallback]
          slug -> slug
        end

      relative = "#{opts[:directory]}/#{base}-#{random_tag()}#{extension}"
      destination = absolute(relative)
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source_path, destination)
      if opts[:remember], do: remember(relative, digest(destination))
      {:ok, relative}
    end
  end

  defp allowed(extension, opts) do
    if extension in opts[:extensions], do: :ok, else: {:error, opts[:refusal]}
  end

  defp readable_image?(path) do
    match?({:ok, _}, Vix.Vips.Image.new_from_file(path))
  end

  # Stored names carry this, so they never collide and may be cached hard.
  defp random_tag, do: 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  ## What a picture is made of

  # Big enough that a photograph is a handful of reads, small enough
  # that nothing sits in memory.
  @digest_chunk 2_097_152

  @doc """
  The SHA-256 of the bytes at `path`, as hex, or nil when the file is
  not there. Two files with the same one are the same picture, whatever
  they are called.
  """
  def digest(path) do
    path
    |> File.stream!(@digest_chunk)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  rescue
    File.Error -> nil
  end

  @doc """
  The path among `paths` that is the same picture as `digest`, or nil.

  A path this has never seen is read once and remembered, so the
  pictures that were on disk before this table existed join it the
  first time their entry takes an upload. Nothing walks the volume.
  """
  def duplicate(digest, paths) when is_binary(digest) do
    paths
    |> known(digest)
    |> Enum.find_value(fn {path, stored} -> if stored == digest, do: path end)
  end

  def duplicate(_digest, _paths), do: nil

  defp known(paths, _digest) do
    paths = Enum.uniq(paths)
    stored = Repo.all(from d in Digest, where: d.path in ^paths, select: {d.path, d.digest})
    missing = paths -- Enum.map(stored, &elem(&1, 0))

    stored ++ Enum.flat_map(missing, &catch_up/1)
  end

  # A picture nobody has read yet. Only pictures: a film is stored as
  # it came and never opened here.
  defp catch_up(relative) do
    with true <- in_dir?(relative, images_dir()),
         digest when is_binary(digest) <- digest(absolute(relative)) do
      remember(relative, digest)
      [{relative, digest}]
    else
      _ -> []
    end
  end

  defp remember(_relative, nil), do: :ok

  defp remember(relative, digest) do
    Repo.insert!(%Digest{path: relative, digest: digest},
      on_conflict: [set: [digest: digest]],
      conflict_target: :path
    )

    :ok
  end

  defp forget(relative), do: Repo.delete_all(from d in Digest, where: d.path == ^relative)

  @doc """
  Removes an uploaded file and everything derived from it: the cached
  renditions of a picture, the converted file and the poster of a
  video. Only paths below `images/` and `videos/` qualify; anything
  else is left alone.

  The paths that arrive here are not all the server's own: deleting a
  text hands over every reference its body ever held, and a body is
  written by hand. A name that climbs out of the uploads root with
  `..` is no upload of ours, whatever it starts with.
  """
  def remove_upload(relative) when is_binary(relative) do
    case under_root(relative) do
      nil -> :ok
      path -> remove_stored_upload(path)
    end
  end

  def remove_upload(_other), do: :ok

  defp remove_stored_upload(relative) do
    cond do
      in_dir?(relative, images_dir()) ->
        remove(relative)
        forget(relative)
        Texttile.Images.drop_renditions(relative)

      in_dir?(relative, videos_dir()) ->
        Texttile.Videos.forget(relative)
        remove(relative)

      true ->
        :ok
    end

    :ok
  end

  defp in_dir?(relative, dir), do: match?([^dir | _rest], Path.split(relative))

  @doc "Back to the default mark: the file goes, the settings clear."
  def reset_site_mark(mark) when mark in @marks do
    remove_stored_file(mark)
    {:ok, _} = Settings.put(mark, nil)
    {:ok, _} = Settings.put(:"#{mark}_name", nil)
    :ok
  end

  defp remove_stored_file(mark) do
    case Settings.get(mark) do
      nil -> :ok
      relative -> remove(relative)
    end
  end
end
