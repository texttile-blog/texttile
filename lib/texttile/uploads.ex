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

  alias Texttile.Settings

  @doc "The uploads root from the install config."
  def root do
    Application.fetch_env!(:texttile, :uploads_path)
  end

  @doc "The absolute path behind a stored relative one."
  def absolute(relative), do: Path.join(root(), relative)

  # The folders of the layout above, in the order the settings screen
  # names them: what came in first, then what the server made of it.
  @report_dirs ~w(images videos site cache)

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
        relative = "site/#{mark}-#{tag}#{extension}"
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
            File.rm(destination)
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
  """
  def put_body_image(source_path, original_name) do
    store(source_path, original_name,
      directory: "images",
      extensions: @body_image_extensions,
      fallback: "image",
      refusal: "PNG, JPG, WebP or GIF, please",
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
      directory: "videos",
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
    if inside_root?(relative) do
      remove_stored_upload(relative)
    else
      :ok
    end
  end

  def remove_upload(_other), do: :ok

  defp remove_stored_upload("images/" <> _ = relative) do
    File.rm(absolute(relative))
    Texttile.Images.drop_renditions(relative)
    :ok
  end

  defp remove_stored_upload("videos/" <> _ = relative) do
    Texttile.Videos.forget(relative)
    File.rm(absolute(relative))
    :ok
  end

  defp remove_stored_upload(_other), do: :ok

  # The same reading the upload routes do: expand the name and see
  # whether it still stands below the root.
  defp inside_root?(relative) do
    root = Path.expand(root())

    root |> Path.join(relative) |> Path.expand() |> String.starts_with?(root <> "/")
  end

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
      relative -> File.rm(absolute(relative))
    end
  end
end
