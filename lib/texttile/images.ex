defmodule Texttile.Images do
  @moduledoc """
  Renditions of uploaded images. The originals are kept as they came;
  what a page shows is scaled so the longer edge stays within the
  Images setting, and nothing is ever scaled up.

  A rendition is made the moment a page first needs it and then answers
  from the cache. Every image holds one cached size at a time: asking
  for a new size drops the old one first, so nothing stale survives.
  The whole cache is disposable; clearing it only costs the next reader
  a moment.
  """

  alias Texttile.Settings
  alias Texttile.Uploads
  alias Vix.Vips

  @cache_dir "cache"

  # Formats vips scales well. Anything else (svg, gif) is answered as it is.
  @scalable ~w(.jpg .jpeg .png .webp)

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
    drop_other_sizes(relative, target)

    cond do
      File.exists?(Uploads.absolute(target)) -> {:ok, target}
      longer_edge(original) <= max_edge -> {:ok, relative}
      true -> create(original, target, max_edge)
    end
  end

  # cache/<original path, slashes flattened>-<edge><ext>
  defp cached_name(relative, max_edge) do
    extension = Path.extname(relative)
    flat = String.replace(relative, "/", "__")
    prefix = binary_part(flat, 0, byte_size(flat) - byte_size(extension))
    "#{@cache_dir}/#{prefix}-#{max_edge}#{extension}"
  end

  defp drop_other_sizes(relative, keep) do
    extension = Path.extname(relative)
    flat = String.replace(relative, "/", "__")
    prefix = binary_part(flat, 0, byte_size(flat) - byte_size(extension)) <> "-"

    case File.ls(Uploads.absolute(@cache_dir)) do
      {:ok, names} ->
        for name <- names,
            String.starts_with?(name, prefix),
            "#{@cache_dir}/#{name}" != keep do
          File.rm(Uploads.absolute("#{@cache_dir}/#{name}"))
        end

        :ok

      {:error, _} ->
        :ok
    end
  end

  defp longer_edge(path) do
    {:ok, image} = Vips.Image.new_from_file(path)
    max(Vips.Image.width(image), Vips.Image.height(image))
  end

  defp create(original, target, max_edge) do
    destination = Uploads.absolute(target)
    File.mkdir_p!(Path.dirname(destination))

    # Written next to its place and renamed, so a reader never meets a
    # half-made file. The name keeps its extension: vips reads the
    # format from it.
    partial = Path.join(Path.dirname(destination), ".tmp-" <> Path.basename(destination))

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

  @doc "Empties the rendition cache. Renditions regenerate on demand."
  def clear_cache do
    File.rm_rf!(Uploads.absolute(@cache_dir))
    :ok
  end

  @doc "The size of the rendition cache on disk, in bytes."
  def cache_bytes do
    case File.ls(Uploads.absolute(@cache_dir)) do
      {:ok, names} ->
        names
        |> Enum.map(&File.stat!(Uploads.absolute("#{@cache_dir}/#{&1}")).size)
        |> Enum.sum()

      {:error, _} ->
        0
    end
  end
end
