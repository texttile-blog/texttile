defmodule Texttile.Export do
  @moduledoc """
  One entry as a bundle in a zip: the text as `index.md`, and every
  picture and film it carries below `gallery/`.

  The bundle is the format IMPORT.md defines, so a zip that leaves here
  comes back through the import unchanged. It is a Hugo page bundle at
  the same time: a folder with an `index.md` and its files beside it,
  addressed by relative path.

  The tiles are numbered in the order a reader meets them, `001_` and
  up, which is the order `gallery_date` gives. The files in the words
  follow their own count under `xxx_`, so a look at the folder says at
  once what stood in the gallery and what stood in the text.

  What travels is the file as it was uploaded, never a rendition, and
  the text is the one the readers have. An entry that was never live
  has only the working copy, and that is what it exports.
  """

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Body
  alias Texttile.Articles.Reading
  alias Texttile.Gallery
  alias Texttile.Uploads

  @uploads_prefix "/uploads/"

  @doc "The name the download carries."
  def zip_name(%Article{} = article), do: folder(article) <> ".zip"

  @doc """
  Writes the bundle of one entry as a zip below `dir` and answers
  `{:ok, path}`. The folder it unpacks to is named after the address of
  the entry.

  The files are copied into `dir` on the way, so nothing bigger than
  one picture stands in memory. `dir` belongs to the caller, who is the
  one that takes it away again.
  """
  def write_zip(%Article{} = article, dir) do
    # The bundle is a reader's copy: it hands on what the site says,
    # never the working copy.
    article = Reading.text(article, :reader)
    folder = folder(article)
    carried = carried(article)

    stage = Path.join(dir, folder)
    File.mkdir_p!(stage)

    # A file can go between the reading of the gallery and the copy: an
    # undo window closes, another admin deletes a tile. That is not an
    # error here, it is one file less, the way a reference whose file
    # has gone is one file less. The bundle is written from what
    # actually arrived.
    carried = Enum.filter(carried, &copied?(&1, stage))

    File.write!(Path.join(stage, "index.md"), index_md(article, carried))

    names = Enum.map(["index.md" | Enum.map(carried, & &1.name)], &~c"#{folder}/#{&1}")
    path = Path.join(dir, zip_name(article))

    case :zip.create(String.to_charlist(path), names, cwd: String.to_charlist(dir)) do
      {:ok, _} -> {:ok, path}
      {:error, reason} -> {:error, "the zip could not be written: #{inspect(reason)}"}
    end
  end

  defp copied?(file, stage) do
    target = Path.join(stage, file.name)
    File.mkdir_p!(Path.dirname(target))

    case File.cp(Uploads.absolute(file.path), target) do
      :ok -> true
      {:error, _gone} -> false
    end
  end

  ## What is in the bundle

  # Every file of the entry, with the name it takes in the bundle: the
  # tiles first, in gallery order, then what stands in the words, in
  # reading order. A file the gallery already carries is not written
  # twice, and a reference whose file has gone is left out; the words
  # then keep the address they had.
  #
  # `url` is the address as the words wrote it, which is what the
  # rewriting looks for; `path` is what that address really names below
  # the uploads root, which is what is read.
  defp carried(article) do
    tiles =
      article.id
      |> Gallery.list()
      |> Enum.filter(&there?(&1.path))
      |> Enum.with_index(1)
      |> Enum.map(fn {image, at} ->
        %{
          path: image.path,
          url: @uploads_prefix <> image.path,
          name: "gallery/#{count(at)}_#{tile_name(image)}"
        }
      end)

    taken = MapSet.new(tiles, & &1.path)

    inline =
      article.body
      |> Body.upload_paths()
      |> Enum.reject(&(&1 in taken))
      |> Enum.flat_map(&below_root/1)
      |> Enum.with_index(1)
      |> Enum.map(fn {{written, path}, at} ->
        %{
          path: path,
          url: @uploads_prefix <> written,
          name: "gallery/xxx_#{count(at)}_#{inline_name(path)}"
        }
      end)

    tiles ++ inline
  end

  # The words are written by hand, so a reference in them can name
  # anything at all. `under_root/1` is the one reading of what an
  # address below the uploads really is; a name that climbs out of the
  # root is no file of ours and travels nowhere.
  defp below_root(written) do
    case Uploads.under_root(written) do
      nil -> []
      path -> if there?(path), do: [{written, path}], else: []
    end
  end

  defp there?(relative), do: File.regular?(Uploads.absolute(relative))

  defp count(at), do: at |> Integer.to_string() |> String.pad_leading(3, "0")

  # A tile keeps the name it was uploaded under; the extension comes
  # from the stored file, which is the one that says what it really is.
  defp tile_name(image) do
    extension = Path.extname(image.path)
    (image.filename |> Path.rootname() |> unnumbered() |> readable()) <> extension
  end

  # A file in the words has no name but the stored one, which carries
  # the random tag that keeps stored names apart. The bundle numbers
  # its files itself, so the tag comes off again.
  defp inline_name(relative) do
    extension = Path.extname(relative)

    relative
    |> Path.basename(extension)
    |> String.replace(~r/-[0-9a-f]{8}\z/, "")
    |> unnumbered()
    |> readable()
    |> Kernel.<>(extension)
  end

  # An entry that came in through an import carries the numbers of the
  # bundle it came from: the importer keeps the bundle name, and the
  # stored name is made from it. Numbering a number would grow a prefix
  # on every trip between two sites, so the old one comes off first.
  # Written with a dash as well, because a stored name is slugified.
  defp unnumbered(name) do
    String.replace(name, ~r/\A(xxx[_-])?\d{3}[_-]/, "")
  end

  # A name a zip, a file system and a Hugo site all take without
  # asking questions.
  defp readable(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9._-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "file"
      clean -> String.slice(clean, 0, 80)
    end
  end

  ## index.md

  defp index_md(article, carried) do
    front_matter(article, carried) <> body(article, carried) <> "\n"
  end

  defp front_matter(article, carried) do
    tiles = Enum.reject(carried, &String.starts_with?(&1.name, "gallery/xxx_"))

    lines =
      [
        {"title", quoted(title(article))},
        {"slug", quoted(said(article.slug))},
        {"date", article.publish_date && Date.to_iso8601(article.publish_date)},
        {"status", status(article)},
        {"type", article.type},
        {"tags", tags(article)},
        {"allow_comments", to_string(article.allow_comments)},
        {"preview", preview(article, carried)}
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.map(fn {key, value} -> "#{key}: #{value}\n" end)

    # The key stands even when the gallery is empty, and that empty list
    # is the point: without the key the import falls back to its
    # shorthand and takes every file in gallery/ for a tile, which would
    # give an entry whose pictures all stood in the words a gallery it
    # never had.
    gallery =
      case tiles do
        [] -> "gallery: []\n"
        tiles -> "gallery:\n" <> Enum.map_join(tiles, fn tile -> "  - #{tile.name}\n" end)
      end

    "---\n" <> Enum.join(lines) <> gallery <> "---\n"
  end

  # The importer needs a title, and an entry does not: an untitled one
  # travels under the name of its folder.
  defp title(article) do
    case String.trim(to_string(article.title)) do
      "" -> folder(article)
      title -> String.replace(title, ~r/\s+/u, " ")
    end
  end

  # A scheduled entry is published with a day still ahead, which is how
  # the importer schedules it again.
  defp status(%Article{status: "draft"}), do: "draft"
  defp status(%Article{}), do: "published"

  defp tags(article) do
    case Articles.tag_list(article) do
      [] -> nil
      tags -> "[" <> Enum.map_join(tags, ", ", &quoted/1) <> "]"
    end
  end

  defp preview(%Article{preview_path: nil}, _carried), do: nil

  defp preview(%Article{preview_path: path}, carried) do
    Enum.find_value(carried, fn file -> file.path == path && file.name end)
  end

  # Every reference the bundle carries points into the folder; one that
  # points somewhere else, or at a file that has gone, stays as it is.
  defp body(article, carried) do
    names = Map.new(carried, fn file -> {file.url, file.name} end)

    Body.rewrite(article.body, fn whole, alt, url ->
      case Map.fetch(names, String.trim(url)) do
        {:ok, name} -> "![#{alt}](#{name})"
        :error -> whole
      end
    end)
  end

  ## Names

  defp folder(%Article{slug: slug} = article) do
    case to_string(slug) do
      "" -> "entry-#{article.id}"
      slug -> slug
    end
  end

  # A field nobody filled in is not written at all.
  defp said(nil), do: nil

  defp said(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      said -> said
    end
  end

  # The front matter is the subset `Texttile.Import.Frontmatter` reads:
  # a quoted value, with the two escapes it knows.
  defp quoted(nil), do: nil

  defp quoted(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    ~s("#{escaped}")
  end
end
