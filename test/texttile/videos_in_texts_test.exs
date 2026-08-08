defmodule Texttile.VideosInTextsTest do
  @moduledoc """
  A video is stored, put into a text or a gallery, shown, and removed.
  The way through the app, not the ffmpeg work (see VideosTest).
  """
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.VideoFixtures

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Uploads
  alias Texttile.Videos

  setup do
    File.rm_rf!(Uploads.root())
    user = user_fixture()
    {:ok, article} = Articles.create_draft(user)
    %{article: article, user: user}
  end

  defp stored_video do
    path = video_file(320, 240)
    {:ok, relative} = Uploads.put_body_video(path, "Harbour Morning.mov")
    relative
  end

  defp converted_video do
    relative = stored_video()
    {:ok, video} = Videos.convert(Videos.ensure(relative))
    {relative, video}
  end

  describe "storing" do
    test "a video goes below videos/, under a readable name" do
      relative = stored_video()

      assert relative =~ ~r"^videos/harbour-morning-\w+\.mov$"
      assert File.exists?(Uploads.absolute(relative))
    end

    test "a file that is no video by its name is refused" do
      assert {:error, message} = Uploads.put_body_video(video_file(320, 240), "clip.txt")
      assert message =~ "MP4"
    end
  end

  describe "the still a page shows for a stored file" do
    test "a picture stands for itself" do
      assert Videos.still("images/a-1234.jpg") == "images/a-1234.jpg"
    end

    test "a video has none until it is converted" do
      relative = stored_video()
      Videos.ensure(relative)

      assert Videos.still(relative) == nil
    end

    test "a converted video stands behind its poster" do
      {relative, video} = converted_video()

      assert Videos.still(relative) == video.poster_path
    end
  end

  describe "the gallery" do
    test "takes a video as a tile", %{article: article} do
      relative = stored_video()

      {:ok, image} = Gallery.add_file(article, Uploads.absolute(relative), "Harbour Morning.mov")

      assert image.path =~ ~r"^videos/"
      assert Gallery.list(article.id) |> Enum.map(& &1.path) == [image.path]
    end

    test "the tile of a converted video is its poster", %{article: article} do
      {:ok, image} =
        Gallery.add_file(article, video_file(320, 240), "Harbour Morning.mov")

      {:ok, video} = Videos.convert(Videos.ensure(image.path))

      assert Videos.still(image.path) == video.poster_path
    end

    test "deleting a tile takes the converted file and the poster", %{article: article} do
      {:ok, image} = Gallery.add_file(article, video_file(320, 240), "clip.mp4")
      {:ok, video} = Videos.convert(Videos.ensure(image.path))

      {:ok, _} = Gallery.delete(article.id, image.id)
      # the undo window has to close before the file goes
      Texttile.Repo.update_all(
        Ecto.Query.from(i in Texttile.Gallery.Image, where: i.id == ^image.id),
        set: [delete_after: DateTime.add(DateTime.utc_now(:microsecond), -1, :second)]
      )

      assert Gallery.sweep_due() == 1
      refute File.exists?(Uploads.absolute(image.path))
      refute File.exists?(Uploads.absolute(video.mp4_path))
      refute File.exists?(Uploads.absolute(video.poster_path))
      assert Videos.get(image.path) == nil
    end

    test "a video without a poster is no preview of a text", %{article: article} do
      {:ok, image} = Gallery.add_file(article, video_file(320, 240), "clip.mp4")

      assert Gallery.previews([article]) == %{}

      {:ok, video} = Videos.convert(Videos.ensure(image.path))

      assert Gallery.previews([article]) == %{article.id => video.poster_path}
    end
  end

  describe "removing a path the writer typed" do
    test "a name that climbs out of the uploads root takes nothing with it" do
      File.mkdir_p!(Uploads.absolute("videos"))
      File.mkdir_p!(Uploads.absolute("images"))
      outside = Path.expand(Path.join(Uploads.root(), "../not-an-upload.txt"))
      File.mkdir_p!(Path.dirname(outside))
      File.write!(outside, "somebody else's file")
      on_exit(fn -> File.rm(outside) end)

      # what a body reference of ![x](/uploads/videos/../../not-an-upload.txt)
      # hands to the delete of a text
      :ok = Uploads.remove_upload("videos/../../not-an-upload.txt")
      :ok = Uploads.remove_upload("images/../../not-an-upload.txt")

      assert File.exists?(outside)
    end
  end

  describe "the text itself" do
    test "deleting a text takes its videos along", %{article: article} do
      relative = stored_video()
      {:ok, video} = Videos.convert(Videos.ensure(relative))
      {:ok, article} = Articles.update_text(article, %{body: "![clip](/uploads/#{relative})"})

      {:ok, _} = Articles.delete_article(article)

      refute File.exists?(Uploads.absolute(relative))
      refute File.exists?(Uploads.absolute(video.mp4_path))
      assert Videos.get(relative) == nil
    end
  end
end
