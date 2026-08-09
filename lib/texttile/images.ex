defmodule Texttile.Images do
  @moduledoc """
  Renditions of uploaded images. The originals are kept as they came;
  what a page shows is scaled so the longer edge stays within the
  Images setting, and nothing is ever scaled up.

  A rendition is made the moment a page first needs it and then answers
  from the cache. An image holds a small, known set of cached sizes:
  the admin thumbnail, the reader size of the moment, and whatever was
  just asked for. Anything else is dropped on the next ask, so nothing
  stale survives. The whole cache is disposable; clearing it only
  costs the next reader a moment.
  """

  alias Texttile.Settings
  alias Texttile.Uploads
  alias Vix.Vips

  @cache_dir "cache"

  # Formats vips scales well. Anything else (svg, gif) is answered as it is.
  @scalable ~w(.jpg .jpeg .png .webp)

  # The fixed edges the site asks for beside the reader size: 320 for
  # the admin thumbnails, 640 for the reader's cards and gallery tiles,
  # 1320 for the pictures inside a text (the 660px column, twice). The
  # gallery lightbox asks for the reader size instead ("max" in the
  # route). Every fixed edge stays sanctioned in the cache; only stale
  # reader sizes are dropped.
  @fixed_edges [320, 640, 1320]

  @doc """
  The path to show for an original, at the current (or given) max edge:
  the cached rendition, made on the fly when it is missing, or the
  original itself while it is small enough. Paths are relative to the
  uploads root.
  """
  def rendition(relative, max_edge \\ nil) do
    max_edge = max_edge || Settings.get(:image_max_edge)
    original = Uploads.absolute(relative)
    extension = relative |> Path.extname() |> String.downcase()

    cond do
      not File.exists?(original) -> {:error, :not_found}
      extension not in @scalable -> {:ok, relative}
      true -> scaled(relative, original, max_edge)
    end
  end

  defp scaled(relative, original, max_edge) do
    target = cached_name(relative, max_edge)
    drop_other_sizes(relative, sanctioned(relative, max_edge))

    cond do
      File.exists?(Uploads.absolute(target)) ->
        {:ok, target}

      true ->
        case longer_edge(original) do
          {:ok, edge} when edge <= max_edge -> {:ok, relative}
          {:ok, _larger} -> create(original, target, max_edge)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # The one derivation of an image's cache identity: the original path
  # with its slashes flattened, minus the extension. A cached rendition
  # is <stem>-<edge><ext> below cache/.
  defp cache_stem(relative) do
    extension = Path.extname(relative)
    flat = String.replace(relative, "/", "__")
    {binary_part(flat, 0, byte_size(flat) - byte_size(extension)), extension}
  end

  defp cached_name(relative, max_edge) do
    {stem, extension} = cache_stem(relative)
    "#{@cache_dir}/#{stem}-#{max_edge}#{extension}"
  end

  # The sizes of one image that may stay cached side by side: the
  # fixed edges, the reader size of the moment, and the one just asked
  # for. Only a stale reader size falls out of this set.
  defp sanctioned(relative, requested) do
    [requested | @fixed_edges ++ [Settings.get(:image_max_edge)]]
    |> Enum.uniq()
    |> Enum.map(&cached_name(relative, &1))
  end

  defp drop_other_sizes(relative, keep) do
    {stem, extension} = cache_stem(relative)
    keep = List.wrap(keep)

    # Only this image's sizes: <stem>-<digits><ext>, exactly. A plain
    # prefix match would also hit "a-b.jpg" while dropping "a.jpg".
    mine = ~r/^#{Regex.escape(stem)}-\d+#{Regex.escape(extension)}$/

    case File.ls(Uploads.absolute(@cache_dir)) do
      {:ok, names} ->
        for name <- names,
            Regex.match?(mine, name),
            "#{@cache_dir}/#{name}" not in keep do
          File.rm(Uploads.absolute("#{@cache_dir}/#{name}"))
        end

        :ok

      {:error, _} ->
        :ok
    end
  end

  defp longer_edge(path) do
    case Vips.Image.new_from_file(path) do
      {:ok, image} -> {:ok, max(Vips.Image.width(image), Vips.Image.height(image))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create(original, target, max_edge) do
    destination = Uploads.absolute(target)
    File.mkdir_p!(Path.dirname(destination))

    # Written under a name of its own and renamed, so a reader never
    # meets a half-made file and two concurrent makers never share a
    # temp file. The name keeps its extension: vips reads the format
    # from it.
    partial =
      Path.join(
        Path.dirname(destination),
        ".tmp-#{System.unique_integer([:positive])}-" <> Path.basename(destination)
      )

    with {:ok, thumb} <-
           Vips.Operation.thumbnail(original, max_edge,
             height: max_edge,
             size: :VIPS_SIZE_DOWN
           ),
         :ok <- Vips.Image.write_to_file(thumb, partial),
         :ok <- File.rename(partial, destination) do
      {:ok, target}
    else
      {:error, reason} ->
        File.rm(partial)
        {:error, reason}
    end
  end

  @doc """
  Writes a copy of `source` at `destination` with the longer edge within
  `max_edge`, never scaled up. For files outside the rendition cache,
  e.g. a site mark at upload time.
  """
  def shrink_to(source, destination, max_edge) do
    with {:ok, thumb} <-
           Vips.Operation.thumbnail(source, max_edge,
             height: max_edge,
             size: :VIPS_SIZE_DOWN
           ) do
      Vips.Image.write_to_file(thumb, destination)
    end
  end

  @doc "Drops every cached rendition of one original, e.g. when it goes."
  def drop_renditions(relative) do
    drop_other_sizes(relative, :none)
  end

  @doc "Empties the rendition cache. Renditions regenerate on demand."
  def clear_cache do
    File.rm_rf!(Uploads.absolute(@cache_dir))
    :ok
  end
end
