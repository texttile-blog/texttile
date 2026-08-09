defmodule Texttile.Gallery do
  @moduledoc """
  The gallery of a text: pictures ordered by `gallery_date`, oldest
  first, the id as the tiebreak. Sorting by hand never invents a new
  ordering concept; a drag only writes a new date between the two
  neighbours it landed on. When two dates sit too close for a midpoint,
  the whole gallery's dates are spread a second apart again, in the
  order the eye already sees.

  The gallery is deliberately not behind the document lock: it is the
  conflict-poor half of the editor, open to every admin at once. Every
  change is broadcast on the article's topics as
  `{:gallery_changed, article_id, %{action:, image_id:, by:}}`.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Gallery.Image
  alias Texttile.Gallery.Sweeper
  alias Texttile.Repo
  alias Texttile.Uploads
  alias Vix.Vips

  # A drop at either end lands this far outside, and a respread places
  # the dates this far apart.
  @step_us 1_000_000

  # How long a deleted picture can come back.
  @undo_seconds 10

  ## Reading

  @doc "The living gallery of a text, in the order readers will see."
  def list(article_id) do
    Image
    |> where([i], i.article_id == ^article_id and is_nil(i.delete_after))
    |> order_by([i], asc: i.gallery_date, asc: i.id)
    |> Repo.all()
  end

  @doc "One living image of this text; raises when it is not there."
  def get!(article_id, image_id) do
    Repo.one!(
      from i in Image,
        where: i.article_id == ^article_id and i.id == ^image_id and is_nil(i.delete_after)
    )
  end

  # Another admin may have deleted the image a heartbeat ago; every
  # mutation answers {:error, :gone} then instead of raising.
  defp fetch(article_id, image_id) do
    Repo.one(
      from i in Image,
        where: i.article_id == ^article_id and i.id == ^image_id and is_nil(i.delete_after)
    )
  end

  @doc """
  The file paths of every image of a text, the pending deletes
  included. For the article's own deletion, which takes the files along.
  """
  def paths(article_id) do
    Repo.all(from i in Image, where: i.article_id == ^article_id, select: i.path)
  end

  @doc """
  The preview image of each given article, as `%{article_id => path}`.
  The texts grid shows it on the card; articles without one are absent.
  """
  def previews(articles) do
    ids = Enum.map(articles, & &1.id)

    by_article =
      Image
      |> where([i], i.article_id in ^ids and is_nil(i.delete_after))
      |> order_by([i], asc: i.gallery_date, asc: i.id)
      |> Repo.all()
      |> Enum.group_by(& &1.article_id, & &1.path)

    Enum.reduce(articles, %{}, fn article, previews ->
      case preview_still(article, Map.get(by_article, article.id, [])) do
        nil -> previews
        path -> Map.put(previews, article.id, path)
      end
    end)
  end

  @doc """
  The pictures a preview can be chosen from: the gallery in its order,
  then the finished pictures inside the text. A video counts with its
  poster, so it joins the list once ffmpeg is through and not before -
  a preview nobody can see is no preview.
  """
  def preview_candidates(article, gallery_paths) do
    (gallery_paths ++ inline_paths(article.body))
    |> Enum.uniq()
    |> Enum.filter(&Texttile.Videos.still/1)
  end

  @doc """
  The preview the readers see: the chosen image while it still exists,
  otherwise the first image of the text, otherwise nil.
  """
  def effective_preview(article, gallery_paths) do
    candidates = preview_candidates(article, gallery_paths)

    if article.preview_path in candidates do
      article.preview_path
    else
      List.first(candidates)
    end
  end

  @doc """
  The gallery as a reader page draws it: one map per tile, with the
  still to show, the film to play behind it, and the original to link.
  Tiles with nothing to show yet - a video ffmpeg has not finished -
  stay out until they have a poster. One query for the whole gallery.
  """
  def tiles(images) do
    stills = Texttile.Videos.stills(Enum.map(images, & &1.path))

    images
    |> Enum.map(fn image ->
      media = stills[image.path]

      %{
        id: image.id,
        filename: image.filename,
        original: image.path,
        still: media.still,
        film: media.film
      }
    end)
    |> Enum.filter(& &1.still)
  end

  @doc """
  The picture a card, a link preview or the texts grid really shows:
  the still behind the chosen preview, and where that has none yet -
  a video still converting - the first candidate that has one.
  """
  def preview_still(article, gallery_paths) do
    case effective_preview(article, gallery_paths) do
      nil -> nil
      path -> Texttile.Videos.still(path)
    end
  end

  defp inline_paths(body) do
    body
    |> Texttile.Articles.inline_refs()
    |> Enum.flat_map(fn
      %{kind: :done, url: "/uploads/" <> relative} -> [relative]
      _ -> []
    end)
  end

  ## Adding

  @doc """
  Stores an uploaded picture or video and puts it into the gallery.
  The file is kept exactly as it came; the gallery date starts as the
  EXIF capture date when the file carries one, otherwise as the upload
  moment. A video stands in line for its conversion right away; the
  tile shows its poster once ffmpeg is through (`Texttile.Videos`).
  """
  def add_file(%Article{} = article, source_path, original_name, opts \\ []) do
    if Texttile.Videos.video?(original_name) do
      add_stored(article, Uploads.put_body_video(source_path, original_name), original_name, opts)
    else
      add_stored(article, Uploads.put_body_image(source_path, original_name), original_name, opts)
    end
  end

  defp add_stored(article, stored, original_name, opts) do
    with {:ok, relative} <- stored do
      # The file went to disk first; a failed insert (say the text was
      # deleted this second) must not leave it orphaned there.
      image =
        try do
          insert_stored(article, relative, original_name, nil)
        rescue
          error ->
            Uploads.remove_upload(relative)
            reraise error, __STACKTRACE__
        end

      broadcast(article.id, :added, image.id, opts[:by])
      {:ok, image}
    end
  end

  @doc """
  The importer's swap: the old rows go, the bundle's tiles come, in the
  given order as `{relative, filename, gallery_date}`, and the open
  editors hear one broadcast for the whole move. The files are not
  touched: the old ones are the caller's to remove once its transaction
  holds, the new ones are stored uploads already.
  """
  def replace_imported(%Article{} = article, tiles) do
    Repo.delete_all(from i in Image, where: i.article_id == ^article.id)

    images =
      Enum.map(tiles, fn {relative, filename, gallery_date} ->
        insert_stored(article, relative, filename, gallery_date)
      end)

    broadcast(article.id, :replaced, nil, nil)
    images
  end

  # The one way a row enters the gallery: the stored file is probed,
  # the row inserted. Without a date the picture speaks for itself
  # (EXIF), and the fallback is this very moment. A video says nothing
  # here; its size comes with the conversion, and so does its poster.
  defp insert_stored(article, relative, filename, gallery_date) do
    {taken, width, height} =
      if Texttile.Videos.video?(relative) do
        {nil, nil, nil}
      else
        probe(Uploads.absolute(relative))
      end

    image =
      Repo.insert!(%Image{
        article_id: article.id,
        path: relative,
        filename: String.slice(filename, 0, 120),
        gallery_date: gallery_date || taken || DateTime.utc_now(:microsecond),
        width: width,
        height: height
      })

    if Texttile.Videos.video?(relative), do: Texttile.Videos.queue(relative)
    image
  end

  # What the CMS wants to know about the stored file: the capture date,
  # and the size the viewer will see (vips renditions honour the EXIF
  # orientation, so a turned photo swaps its edges here too).
  defp probe(absolute) do
    case Vips.Image.new_from_file(absolute) do
      {:ok, image} ->
        width = Vips.Image.width(image)
        height = Vips.Image.height(image)

        {width, height} =
          case Vips.Image.header_value(image, "orientation") do
            {:ok, orientation} when orientation in 5..8 -> {height, width}
            _ -> {width, height}
          end

        {taken_at(image), width, height}

      {:error, _} ->
        {nil, nil, nil}
    end
  end

  defp taken_at(image) do
    ["exif-ifd2-DateTimeOriginal", "exif-ifd0-DateTime"]
    |> Enum.find_value(fn field ->
      case Vips.Image.header_value(image, field) do
        {:ok, raw} -> parse_exif_datetime(raw)
        {:error, _} -> nil
      end
    end)
  end

  # EXIF writes "2024:05:01 12:30:45"; vips appends a describing tail.
  defp parse_exif_datetime(raw) do
    with [_, date, time] <- Regex.run(~r/\A(\d{4}:\d{2}:\d{2}) (\d{2}:\d{2}:\d{2})/, raw),
         iso = String.replace(date, ":", "-") <> "T" <> time,
         {:ok, naive} <- NaiveDateTime.from_iso8601(iso) do
      as_utc(naive)
    else
      _ -> nil
    end
  end

  ## The date, the one ordering

  @doc """
  Sets the gallery date from what the lightbox input sends: a full ISO
  moment, or the `YYYY-MM-DDTHH:MM[:SS]` of a datetime-local field,
  read as the naive wall-clock time the whole gallery speaks.
  """
  def set_date(article_id, image_id, value, opts \\ []) do
    with {:ok, date} <- parse_date(to_string(value)),
         %Image{} = image <- fetch(article_id, image_id) do
      image = image |> Ecto.Changeset.change(gallery_date: date) |> Repo.update!()
      broadcast(article_id, :date, image.id, opts[:by])
      {:ok, image}
    else
      nil -> {:error, :gone}
      error -> error
    end
  end

  defp parse_date(value) do
    padded =
      if String.match?(value, ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/) do
        value <> ":00"
      else
        value
      end

    case DateTime.from_iso8601(padded) do
      {:ok, date, _offset} ->
        {:ok, %{date | microsecond: {elem(date.microsecond, 0), 6}}}

      {:error, _} ->
        case NaiveDateTime.from_iso8601(padded) do
          {:ok, naive} -> {:ok, as_utc(naive)}
          {:error, _} -> {:error, :invalid_date}
        end
    end
  end

  defp as_utc(naive) do
    date = DateTime.from_naive!(naive, "Etc/UTC")
    %{date | microsecond: {elem(date.microsecond, 0), 6}}
  end

  ## Sorting

  @doc """
  Moves one image to where it was dropped. `ids` is the full new order
  as the client shows it; anything less than a complete, exact naming
  of the gallery is refused. Only the moved image's date changes - the
  midpoint of its new neighbours, or a step outside at either end -
  unless no midpoint is left, in which case every date is respread and
  the visible order kept.
  """
  def reorder(article_id, moved_id, ids, opts \\ []) do
    images = list(article_id)
    by_id = Map.new(images, &{&1.id, &1})

    complete? =
      ids != [] and
        length(ids) == map_size(by_id) and
        MapSet.new(ids) == MapSet.new(Map.keys(by_id)) and
        Map.has_key?(by_id, moved_id)

    if complete? do
      index = Enum.find_index(ids, &(&1 == moved_id))
      left = neighbour(by_id, ids, index - 1)
      right = neighbour(by_id, ids, index + 1)

      case placement(left, right) do
        :keep ->
          {:ok, by_id[moved_id]}

        {:ok, date} ->
          image =
            by_id[moved_id]
            |> Ecto.Changeset.change(gallery_date: date)
            |> Repo.update!()

          broadcast(article_id, :reordered, image.id, opts[:by])
          {:ok, image}

        :respread ->
          image = respread(by_id, ids, moved_id)
          broadcast(article_id, :reordered, moved_id, opts[:by])
          {:ok, image}
      end
    else
      {:error, :invalid_order}
    end
  end

  defp neighbour(_by_id, _ids, index) when index < 0, do: nil
  defp neighbour(by_id, ids, index), do: by_id[Enum.at(ids, index)]

  defp placement(nil, nil), do: :keep
  defp placement(nil, right), do: {:ok, DateTime.add(right.gallery_date, -@step_us, :microsecond)}
  defp placement(left, nil), do: {:ok, DateTime.add(left.gallery_date, @step_us, :microsecond)}

  defp placement(left, right) do
    room = DateTime.diff(right.gallery_date, left.gallery_date, :microsecond)

    if room > 1 do
      {:ok, DateTime.add(left.gallery_date, div(room, 2), :microsecond)}
    else
      :respread
    end
  end

  # Every image a second apart, starting at the earliest date the
  # gallery already had, in the order the client shows.
  defp respread(by_id, ids, moved_id) do
    base =
      by_id
      |> Map.values()
      |> Enum.map(& &1.gallery_date)
      |> Enum.min(DateTime)

    {:ok, moved} =
      Repo.transaction(fn ->
        ids
        |> Enum.with_index()
        |> Enum.map(fn {id, index} ->
          by_id[id]
          |> Ecto.Changeset.change(
            gallery_date: DateTime.add(base, index * @step_us, :microsecond)
          )
          |> Repo.update!()
        end)
        |> Enum.find(&(&1.id == moved_id))
      end)

    moved
  end

  ## Deleting, with the way back

  @doc """
  Takes an image out of the gallery at once and opens the ten second
  undo window. The file stays until the window has closed.

  `now:` names the moment the window starts from. It defaults to this
  one, so callers say nothing and tests name the moment they mean.
  """
  def delete(article_id, image_id, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    delete_after = DateTime.add(now, @undo_seconds, :second)

    case fetch(article_id, image_id) do
      nil ->
        {:error, :gone}

      image ->
        image = image |> Ecto.Changeset.change(delete_after: delete_after) |> Repo.update!()
        broadcast(article_id, :deleted, image.id, opts[:by])
        Sweeper.schedule(delete_after)
        {:ok, image}
    end
  end

  @doc """
  Puts a deleted image back, as long as its window is still open at
  `now:`, which defaults to this moment.
  """
  def undo(article_id, image_id, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)

    query =
      from i in Image,
        where:
          i.article_id == ^article_id and i.id == ^image_id and
            not is_nil(i.delete_after) and i.delete_after > ^now

    case Repo.one(query) do
      nil ->
        {:error, :gone}

      image ->
        image = image |> Ecto.Changeset.change(delete_after: nil) |> Repo.update!()
        broadcast(article_id, :restored, image.id, opts[:by])
        {:ok, image}
    end
  end

  @doc """
  Makes every deletion final that is overdue at `now`, which defaults
  to this moment: the row goes, then the file and its renditions.
  Answers how many images went.
  """
  def sweep_due(now \\ DateTime.utc_now(:microsecond)) do
    due =
      Repo.all(from i in Image, where: not is_nil(i.delete_after) and i.delete_after <= ^now)

    Enum.each(due, fn image ->
      # by id, not by struct: a row a second sweep already took must
      # not raise as stale here
      Repo.delete_all(from i in Image, where: i.id == ^image.id)
      Uploads.remove_upload(image.path)
    end)

    length(due)
  end

  @doc "The next moment the sweeper has to wake, or nil."
  def next_due do
    Repo.one(from i in Image, where: not is_nil(i.delete_after), select: min(i.delete_after))
  end

  ## PubSub

  # The same two topics Texttile.Articles speaks on: the admin-wide one
  # for the texts grid, the article's own for the open editors.
  defp broadcast(article_id, action, image_id, by) do
    message = {:gallery_changed, article_id, %{action: action, image_id: image_id, by: by}}
    Phoenix.PubSub.broadcast(Texttile.PubSub, "articles", message)
    Phoenix.PubSub.broadcast(Texttile.PubSub, "article:#{article_id}", message)
  end
end
