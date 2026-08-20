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

  @cache_dir Uploads.cache_dir()

  # Formats vips scales well. Anything else (svg, gif) is answered as it is.
  @scalable ~w(.jpg .jpeg .png .webp)

  # The fixed edges the site asks for beside the reader size: 320 for
  # the admin thumbnails, 640 for the reader's cards and gallery tiles,
  # 1320 for the pictures inside a text (the 660px column, twice). The
  # gallery lightbox asks for the reader size instead ("max" in the
  # route). Every fixed edge stays sanctioned in the cache; only stale
  # reader sizes are dropped.
  @fixed_edges [320, 640, 1320]

  # Each use a page has for a stored picture, and the edge it is shown
  # at. The names are the interface; the numbers stay in here.
  @edges %{thumb: 320, card: 640, reading: 1320}

  @doc """
  The address a browser fetches a stored file at, for a named use:
  `:thumb` for an admin thumbnail, `:card` for the reader's cards and
  gallery tiles, `:reading` for a picture inside a text, `:max` for the
  lightbox, and `:original` for the file itself. `path` is relative to
  the uploads root, the way everything stores it.

  Every address for a stored file is built here and nowhere else, so
  the routes and the escaping have one place to change.
  """
  def url(path, use) when is_map_key(@edges, use),
    do: "/renditions/#{@edges[use]}/#{escape(path)}"

  def url(path, :max), do: "/renditions/max/#{escape(path)}"
  def url(path, :original), do: "/uploads/#{escape(path)}"

  # A quote is the one character a stored name can carry that breaks
  # out of a CSS url('...'); everywhere else the escape is harmless.
  defp escape(path), do: String.replace(path, "'", "%27")

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
          Uploads.remove("#{@cache_dir}/#{name}")
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

  # The square a phone puts on its home screen. A phone takes no SVG
  # there and no tab-sized picture either, so the icon is rendered
  # from whatever the site wears in the tab and cached like every
  # other rendition.
  @touch_edge 180
  # Air around the mark, so the rounded mask a phone lays over the
  # square does not cut into it.
  @touch_pad 18
  @bundled_mark "priv/static/images/texttile-mark.svg"

  @doc """
  The icon for the home screen: the uploaded favicon, or the bundled
  Texttile mark, as a #{@touch_edge} px PNG below the cache. The name
  carries the favicon's own, so a new favicon is a new file and the
  earlier one goes with it.
  """
  def touch_icon do
    source = touch_source()
    target = "#{@cache_dir}/touch-#{Path.basename(source, Path.extname(source))}.png"

    if File.exists?(Uploads.absolute(target)) do
      {:ok, target}
    else
      make_touch_icon(source, target)
    end
  end

  # The uploaded favicon while its file is there, the bundled mark
  # otherwise: an icon of the wrong blog would be worse than none, but
  # a settings row pointing at nothing is not the wrong blog.
  defp touch_source do
    with stored when is_binary(stored) <- Settings.get(:favicon),
         path = Uploads.absolute(stored),
         true <- File.exists?(path) do
      path
    else
      _ -> Application.app_dir(:texttile, @bundled_mark)
    end
  end

  defp make_touch_icon(source, target) do
    destination = Uploads.absolute(target)
    File.mkdir_p!(Path.dirname(destination))
    drop_other_touch_icons(target)

    # A name of its own, like every other rendition: a reader never
    # meets a half-made file, and two makers at once never share one.
    partial =
      Path.join(
        Path.dirname(destination),
        ".tmp-#{System.unique_integer([:positive])}-" <> Path.basename(destination)
      )

    inner = @touch_edge - 2 * @touch_pad
    ground = touch_ground()

    with {:ok, thumb} <- Vips.Operation.thumbnail(source, inner, height: inner),
         {:ok, colour} <- Vips.Operation.colourspace(thumb, :VIPS_INTERPRETATION_sRGB),
         {:ok, opaque} <- flattened(colour, ground),
         {:ok, square} <- centred(opaque, ground),
         :ok <- Vips.Image.write_to_file(square, partial),
         :ok <- File.rename(partial, destination) do
      {:ok, target}
    else
      {:error, reason} ->
        File.rm(partial)
        {:error, reason}
    end
  end

  # Only a picture that carries transparency is laid on the ground:
  # vips reads the last band of any other one as its alpha and gives
  # back an error, or a colour nobody chose.
  defp flattened(image, ground) do
    if Vips.Image.has_alpha?(image),
      do: Vips.Operation.flatten(image, background: ground),
      else: {:ok, image}
  end

  # The rendering keeps its ratio, so a favicon that is not square
  # stands in the middle of the square instead of in a corner.
  defp centred(image, ground) do
    left = div(@touch_edge - Vips.Image.width(image), 2)
    top = div(@touch_edge - Vips.Image.height(image), 2)

    Vips.Operation.embed(image, left, top, @touch_edge, @touch_edge,
      extend: :VIPS_EXTEND_BACKGROUND,
      background: ground
    )
  end

  # The icon carries no transparency: a home screen paints one over
  # black, and the ink of the mark is nearly black itself. The ground
  # is the colour the browser paints its own chrome with, so the
  # square and the site agree.
  defp touch_ground do
    case Settings.theme_color() do
      "#" <> <<r::binary-2, g::binary-2, b::binary-2>> ->
        Enum.map([r, g, b], &(String.to_integer(&1, 16) * 1.0))

      _ ->
        [255.0, 255.0, 255.0]
    end
  end

  # The icon of an earlier favicon answers nobody any more.
  defp drop_other_touch_icons(keep) do
    with {:ok, names} <- File.ls(Uploads.absolute(@cache_dir)) do
      for name <- names,
          String.starts_with?(name, "touch-"),
          String.ends_with?(name, ".png"),
          "#{@cache_dir}/#{name}" != keep,
          do: Uploads.remove("#{@cache_dir}/#{name}")
    end

    :ok
  end

  @doc "Drops every cached rendition of one original, e.g. when it goes."
  def drop_renditions(relative) do
    drop_other_sizes(relative, :none)
  end

  @doc "Empties the rendition cache. Renditions regenerate on demand."
  def clear_cache do
    Uploads.remove_dir(@cache_dir)
    :ok
  end
end
