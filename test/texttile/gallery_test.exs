defmodule Texttile.GalleryTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  defp article! do
    user = user_fixture()
    {:ok, article} = Articles.create_draft(user)
    {article, user}
  end

  # Writes a real JPEG into a temp place, optionally with an EXIF
  # capture date, and answers its path.
  defp source_jpg(opts \\ []) do
    width = Keyword.get(opts, :width, 20)
    height = Keyword.get(opts, :height, 10)
    path = Path.join(System.tmp_dir!(), "gallery-#{System.unique_integer([:positive])}.jpg")

    {:ok, black} = Vix.Vips.Operation.black(width, height)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        if taken = opts[:taken] do
          :ok = Vix.Vips.MutableImage.set(mut, "exif-ifd2-DateTimeOriginal", :gchararray, taken)
        end

        if orientation = opts[:orientation] do
          :ok = Vix.Vips.MutableImage.set(mut, "orientation", :gint, orientation)
        end

        :ok
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  defp add!(article, name, opts \\ []) do
    {:ok, image} = Gallery.add_file(article, source_jpg(opts), name)
    image
  end

  defp set_date!(article, image, iso) do
    {:ok, image} = Gallery.set_date(article.id, image.id, iso)
    image
  end

  defp ids(article), do: article.id |> Gallery.list() |> Enum.map(& &1.id)

  describe "add_file/4" do
    test "stores the file below images/ and answers a finished image" do
      {article, _user} = article!()

      {:ok, image} = Gallery.add_file(article, source_jpg(), "Harbor Pier.jpg")

      assert image.article_id == article.id
      assert image.path =~ ~r"^images/harbor-pier-[0-9a-f]{8}\.jpg$"
      assert image.filename == "Harbor Pier.jpg"
      assert image.width == 20
      assert image.height == 10
      assert File.exists?(Uploads.absolute(image.path))
    end

    test "takes the gallery date from the EXIF capture date" do
      {article, _user} = article!()

      image = add!(article, "a.jpg", taken: "2024:05:01 12:30:45")

      assert image.gallery_date == ~U[2024-05-01 12:30:45.000000Z]
    end

    test "falls back to the upload moment without EXIF" do
      {article, _user} = article!()

      image = add!(article, "a.jpg")

      assert DateTime.diff(DateTime.utc_now(), image.gallery_date, :second) in 0..5
    end

    test "stores the dimensions the viewer will see, not the sensor's" do
      {article, _user} = article!()

      image = add!(article, "a.jpg", width: 20, height: 10, orientation: 6)

      assert {image.width, image.height} == {10, 20}
    end

    test "refuses a file that is not an image" do
      {article, _user} = article!()
      path = Path.join(System.tmp_dir!(), "not-an-image.jpg")
      File.write!(path, "plain words")

      assert {:error, _message} = Gallery.add_file(article, path, "not-an-image.jpg")
    end

    test "announces the new image on the article topic" do
      {article, user} = article!()
      Articles.subscribe(article.id)

      {:ok, image} = Gallery.add_file(article, source_jpg(), "a.jpg", by: user.id)

      article_id = article.id
      image_id = image.id
      user_id = user.id

      assert_receive {:gallery_changed, ^article_id,
                      %{action: :added, image_id: ^image_id, by: ^user_id}}
    end
  end

  describe "list/1" do
    test "orders by gallery date, oldest first, id as the tiebreak" do
      {article, _user} = article!()
      b = add!(article, "b.jpg", taken: "2024:05:02 09:00:00")
      a = add!(article, "a.jpg", taken: "2024:05:01 09:00:00")
      same_as_b = add!(article, "c.jpg", taken: "2024:05:02 09:00:00")

      assert ids(article) == [a.id, b.id, same_as_b.id]
    end
  end

  describe "reorder/4" do
    test "a drop between two neighbours lands on their midpoint, neighbours untouched" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg", taken: "2024:05:01 12:00:00")
      c = add!(article, "c.jpg", taken: "2024:05:01 14:00:00")

      {:ok, moved} = Gallery.reorder(article.id, c.id, [a.id, c.id, b.id])

      assert moved.gallery_date == ~U[2024-05-01 11:00:00.000000Z]
      assert ids(article) == [a.id, c.id, b.id]
      assert Gallery.get!(article.id, a.id).gallery_date == a.gallery_date
      assert Gallery.get!(article.id, b.id).gallery_date == b.gallery_date
    end

    test "a drop at the front lands one second before the first" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg", taken: "2024:05:01 12:00:00")

      {:ok, moved} = Gallery.reorder(article.id, b.id, [b.id, a.id])

      assert moved.gallery_date == ~U[2024-05-01 09:59:59.000000Z]
      assert ids(article) == [b.id, a.id]
    end

    test "a drop at the end lands one second after the last" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg", taken: "2024:05:01 12:00:00")

      {:ok, moved} = Gallery.reorder(article.id, a.id, [b.id, a.id])

      assert moved.gallery_date == ~U[2024-05-01 12:00:01.000000Z]
    end

    test "with no room left the dates are redistributed, the order stays" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg")
      c = add!(article, "c.jpg")
      set_date!(article, b, "2024-05-01T10:00:00.000001Z")
      set_date!(article, c, "2024-05-01T10:00:00.000002Z")

      {:ok, _moved} = Gallery.reorder(article.id, c.id, [a.id, c.id, b.id])

      assert ids(article) == [a.id, c.id, b.id]

      dates = article.id |> Gallery.list() |> Enum.map(& &1.gallery_date)

      for [left, right] <- Enum.chunk_every(dates, 2, 1, :discard) do
        assert DateTime.diff(right, left, :microsecond) > 1
      end
    end

    test "keeps working after a redistribution" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg")
      c = add!(article, "c.jpg")
      set_date!(article, b, "2024-05-01T10:00:00.000001Z")
      set_date!(article, c, "2024-05-01T10:00:00.000002Z")

      {:ok, _} = Gallery.reorder(article.id, c.id, [a.id, c.id, b.id])
      {:ok, _} = Gallery.reorder(article.id, b.id, [b.id, a.id, c.id])

      assert ids(article) == [b.id, a.id, c.id]
    end

    test "refuses an order that does not name every image exactly once" do
      {article, _user} = article!()
      a = add!(article, "a.jpg")
      b = add!(article, "b.jpg")

      assert {:error, :invalid_order} = Gallery.reorder(article.id, a.id, [a.id])
      assert {:error, :invalid_order} = Gallery.reorder(article.id, a.id, [a.id, a.id])
      assert {:error, :invalid_order} = Gallery.reorder(article.id, 0, [a.id, b.id])
    end
  end

  describe "set_date/4" do
    test "accepts the minute precision a datetime-local input sends" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")

      {:ok, updated} = Gallery.set_date(article.id, image.id, "2024-05-01T10:32")

      assert updated.gallery_date == ~U[2024-05-01 10:32:00.000000Z]
    end

    test "accepts seconds too" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")

      {:ok, updated} = Gallery.set_date(article.id, image.id, "2024-05-01T10:32:48")

      assert updated.gallery_date == ~U[2024-05-01 10:32:48.000000Z]
    end

    test "refuses what no calendar accepts" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")

      assert {:error, :invalid_date} = Gallery.set_date(article.id, image.id, "yesterday")
      assert {:error, :invalid_date} = Gallery.set_date(article.id, image.id, "")
    end
  end

  describe "delete, undo and the sweep" do
    test "a deleted image leaves the gallery at once, the file stays for the undo" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")

      {:ok, deleted} = Gallery.delete(article.id, image.id)

      assert deleted.delete_after
      assert ids(article) == []
      assert File.exists?(Uploads.absolute(image.path))
    end

    test "undo puts the image back at its former position" do
      {article, _user} = article!()
      a = add!(article, "a.jpg", taken: "2024:05:01 10:00:00")
      b = add!(article, "b.jpg", taken: "2024:05:01 11:00:00")
      c = add!(article, "c.jpg", taken: "2024:05:01 12:00:00")

      {:ok, _} = Gallery.delete(article.id, b.id)
      {:ok, restored} = Gallery.undo(article.id, b.id)

      assert restored.delete_after == nil
      assert ids(article) == [a.id, b.id, c.id]
    end

    test "a picture already deleted answers gone to every late hand" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")
      {:ok, _} = Gallery.delete(article.id, image.id)

      assert {:error, :gone} = Gallery.set_date(article.id, image.id, "2024-05-01T10:00")
      assert {:error, :gone} = Gallery.delete(article.id, image.id)
    end

    test "after the deadline the undo answers gone" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")
      {:ok, _} = Gallery.delete(article.id, image.id)

      assert {:error, :gone} = Gallery.undo(article.id, image.id, now: a_minute_on())
    end

    test "the sweep removes the due image, its file and its renditions" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")
      {:ok, _} = Gallery.delete(article.id, image.id)

      assert Gallery.sweep_due(a_minute_on()) == 1
      assert Repo.get(Gallery.Image, image.id) == nil
      refute File.exists?(Uploads.absolute(image.path))
    end

    test "the sweep leaves images whose undo window is still open" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")
      {:ok, _} = Gallery.delete(article.id, image.id)

      assert Gallery.sweep_due() == 0
      assert Repo.get(Gallery.Image, image.id)
    end

    test "the window is measured from the moment the caller names" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")
      long_ago = DateTime.add(DateTime.utc_now(:microsecond), -1, :hour)

      {:ok, _} = Gallery.delete(article.id, image.id, now: long_ago)

      assert Gallery.sweep_due() == 1
      assert Repo.get(Gallery.Image, image.id) == nil
    end

    # A minute is well past the ten second window and asks for no clock
    # of its own: the test names the moment it wants to be judged at.
    defp a_minute_on, do: DateTime.add(DateTime.utc_now(:microsecond), 60, :second)
  end

  describe "previews" do
    defp reload(article), do: Articles.get_article!(article.id)

    test "without a choice the first image speaks for the text" do
      {article, _user} = article!()
      {other, _user} = article!()
      _late = add!(article, "b.jpg", taken: "2024:05:02 09:00:00")
      first = add!(article, "a.jpg", taken: "2024:05:01 09:00:00")

      assert Gallery.previews([reload(article), other]) == %{article.id => first.path}
    end

    test "a chosen image wins while it exists" do
      {article, _user} = article!()
      _first = add!(article, "a.jpg", taken: "2024:05:01 09:00:00")
      chosen = add!(article, "b.jpg", taken: "2024:05:02 09:00:00")

      {:ok, _} = Articles.update_settings(article, %{preview_path: chosen.path})

      assert Gallery.previews([reload(article)]) == %{article.id => chosen.path}
    end

    test "a stale choice falls back to the first image" do
      {article, _user} = article!()
      first = add!(article, "a.jpg", taken: "2024:05:01 09:00:00")

      {:ok, _} = Articles.update_settings(article, %{preview_path: "images/gone-00000000.jpg"})

      assert Gallery.previews([reload(article)]) == %{article.id => first.path}
    end

    test "a picture inside the text can be the preview too" do
      {article, _user} = article!()

      {:ok, article} =
        Articles.update_text(article, %{body: "![pier](/uploads/images/pier-abcd.jpg)"})

      assert Gallery.preview_candidates(article, []) == ["images/pier-abcd.jpg"]
      assert Gallery.previews([article]) == %{article.id => "images/pier-abcd.jpg"}
    end
  end

  describe "deleting the article" do
    test "takes the gallery files with it" do
      {article, _user} = article!()
      image = add!(article, "a.jpg")

      {:ok, _} = Articles.delete_article(article)

      assert Repo.get(Gallery.Image, image.id) == nil
      refute File.exists?(Uploads.absolute(image.path))
    end
  end
end
