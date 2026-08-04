defmodule Texttile.Uploads do
  @moduledoc """
  The uploaded files on disk. Everything lives below one root from the
  install config (`UPLOADS_PATH`), so one volume carries it all: the
  same layout on a laptop, in a container and on Fly.

      site/    the logo and the favicon
      images/  the originals of every picture (comes with the editor)
      cache/   renditions, disposable (see Texttile.Images)
  """

  alias Texttile.Settings

  @doc "The uploads root from the install config."
  def root do
    Application.fetch_env!(:texttile, :uploads_path)
  end

  @doc "The absolute path behind a stored relative one."
  def absolute(relative), do: Path.join(root(), relative)

  @marks [:logo, :favicon]
  @mark_extensions ~w(.svg .png .jpg .jpeg .webp)

  # A mark is shown small everywhere: ~21 css px in the bar, up to 32 in
  # a browser tab. 4x that stays sharp on any pixel density and keeps a
  # multi-megapixel upload from riding along on every page.
  @mark_max_edge 128

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
        tag = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
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
    extension = original_name |> Path.extname() |> String.downcase()

    cond do
      extension not in @body_image_extensions ->
        {:error, "PNG, JPG, WebP or GIF, please"}

      not readable_image?(source_path) ->
        {:error, "The file could not be read as an image"}

      true ->
        base =
          case Texttile.Articles.slugify(Path.rootname(original_name)) do
            "" -> "image"
            slug -> slug
          end

        tag = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
        relative = "images/#{base}-#{tag}#{extension}"
        destination = absolute(relative)
        File.mkdir_p!(Path.dirname(destination))
        File.cp!(source_path, destination)
        {:ok, relative}
    end
  end

  defp readable_image?(path) do
    match?({:ok, _}, Vix.Vips.Image.new_from_file(path))
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
