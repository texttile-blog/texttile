defmodule Texttile.VideosTest do
  use Texttile.DataCase, async: false

  import Texttile.VideoFixtures

  alias Texttile.Settings
  alias Texttile.Uploads
  alias Texttile.Videos

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  defp stored(path) do
    {:ok, relative} = Uploads.put_body_video(path, Path.basename(path))
    relative
  end

  defp size(relative) do
    {out, 0} =
      System.cmd("ffprobe", [
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "csv=p=0",
        Uploads.absolute(relative)
      ])

    out |> String.trim() |> String.split(",") |> Enum.map(&String.to_integer/1)
  end

  describe "what counts as a video" do
    test "the containers a camera and a phone write" do
      assert Videos.video?("holiday.mp4")
      assert Videos.video?("holiday.MOV")
      assert Videos.video?("holiday.webm")
      assert Videos.video?("holiday.mkv")
      refute Videos.video?("holiday.jpg")
      refute Videos.video?("holiday")
    end
  end

  describe "the ffmpeg command" do
    test "runs on one thread and at the lowest priority" do
      {command, args} = Videos.encode_command("in.mov", "out.mp4", 1280)

      assert Path.basename(command) in ~w(nice ionice)
      assert "19" in args
      assert Enum.find_index(args, &(&1 == "-threads")) |> then(&Enum.at(args, &1 + 1)) == "1"
      assert "libx264" in args
      assert "aac" in args
      assert "+faststart" in args
    end

    test "caps the longer edge and never scales up" do
      {_command, args} = Videos.encode_command("in.mov", "out.mp4", 1280)
      filter = Enum.at(args, Enum.find_index(args, &(&1 == "-vf")) + 1)

      assert filter =~ "min(1280,iw)"
      assert filter =~ "force_original_aspect_ratio=decrease"
      assert filter =~ "force_divisible_by=2"
    end

    test "gives up before it can hold the queue for a day" do
      {_command, args} = Videos.encode_command("in.mov", "out.mp4", 1280)
      limit = Enum.at(args, Enum.find_index(args, &(&1 == "-timelimit")) + 1)

      assert String.to_integer(limit) > 0
    end
  end

  describe "converting" do
    test "makes one mp4 and a poster from the stored original" do
      relative = stored(video_file(640, 480))

      assert {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert video.state == "done"
      assert video.mp4_path =~ ~r"^videos/.*\.web\.mp4$"
      assert video.poster_path =~ ~r"^videos/.*\.poster\.jpg$"
      assert File.exists?(Uploads.absolute(video.mp4_path))
      assert File.exists?(Uploads.absolute(video.poster_path))
      assert video.width == 640
      assert video.height == 480
    end

    test "the original stays as it came" do
      original = video_file(640, 480)
      relative = stored(original)
      before = File.stat!(Uploads.absolute(relative))

      {:ok, _video} = Videos.convert(Videos.ensure(relative))

      assert File.stat!(Uploads.absolute(relative)).size == before.size
    end

    test "the longer edge stays within the setting" do
      {:ok, _} = Settings.put(:video_max_edge, 480)
      relative = stored(video_file(960, 720))

      {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert [480, _height] = size(video.mp4_path)
      assert video.width == 480
    end

    test "a standing video is capped on its height" do
      {:ok, _} = Settings.put(:video_max_edge, 480)
      relative = stored(video_file(720, 960))

      {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert video.height == 480
      assert video.width < 480
    end

    test "a small video is never scaled up" do
      {:ok, _} = Settings.put(:video_max_edge, 1280)
      relative = stored(video_file(320, 240))

      {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert {video.width, video.height} == {320, 240}
    end

    test "a clip too short for the poster frame still comes through" do
      relative = stored(video_file(320, 240, seconds: 0.4))

      assert {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert video.state == "done"
      assert File.exists?(Uploads.absolute(video.mp4_path))
      assert File.exists?(Uploads.absolute(video.poster_path))
    end

    test "a converted file that cannot be put in place fails, and leaves nothing" do
      relative = stored(video_file(320, 240))
      video = Videos.ensure(relative)

      # a directory where the converted file wants to go: the rename
      # cannot happen, whatever ffmpeg made
      File.mkdir_p!(Uploads.absolute(String.replace(relative, ".mp4", ".web.mp4")))

      assert {:error, failed} = Videos.convert(video)

      assert failed.state == "failed"
      assert failed.error =~ "stayed put"
      assert Videos.playback(relative) == nil

      leftovers =
        Uploads.absolute("videos") |> File.ls!() |> Enum.filter(&String.starts_with?(&1, ".tmp-"))

      assert leftovers == []
    end

    test "a file ffmpeg cannot read fails with a reason" do
      relative = stored(broken_video_file())

      assert {:error, video} = Videos.convert(Videos.ensure(relative))

      assert video.state == "failed"
      assert video.error != nil
      assert Videos.playback(relative) == nil
    end

    test "a half written conversion leaves nothing behind" do
      relative = stored(broken_video_file())

      {:error, _video} = Videos.convert(Videos.ensure(relative))

      leftovers =
        Uploads.absolute("videos") |> File.ls!() |> Enum.filter(&String.starts_with?(&1, "."))

      assert leftovers == []
    end
  end

  describe "what a page can show" do
    test "nothing while the conversion is still waiting" do
      relative = stored(video_file(320, 240))
      Videos.ensure(relative)

      assert Videos.get(relative).state == "queued"
      assert Videos.playback(relative) == nil
      assert Videos.poster(relative) == nil
    end

    test "the mp4, the poster and the size once it is done" do
      relative = stored(video_file(320, 240))
      {:ok, video} = Videos.convert(Videos.ensure(relative))

      assert Videos.get(relative).state == "done"
      assert Videos.poster(relative) == video.poster_path

      assert %{mp4: mp4, poster: poster, width: 320, height: 240} = Videos.playback(relative)
      assert mp4 == video.mp4_path
      assert poster == video.poster_path
    end

    test "nothing at all for a file nobody uploaded" do
      assert Videos.get("videos/never-there.mp4") == nil
      assert Videos.playback("videos/never-there.mp4") == nil
    end
  end

  describe "a video that goes while ffmpeg works" do
    test "the conversion drops its files instead of orphaning them" do
      relative = stored(video_file(320, 240))
      video = Videos.ensure(relative)

      # the text was deleted while ffmpeg ran: the row is gone before
      # the conversion writes its result
      Texttile.Repo.delete_all(
        Ecto.Query.from(v in Texttile.Videos.Video, where: v.path == ^relative)
      )

      assert Videos.convert(video) == {:error, :gone}

      leftovers =
        Uploads.absolute("videos") |> File.ls!() |> Enum.reject(&(&1 == Path.basename(relative)))

      assert leftovers == []
      assert Videos.get(relative) == nil
    end

    test "removing takes the derived files even while none are recorded" do
      relative = stored(video_file(320, 240))
      Videos.ensure(relative)

      # what a conversion writes just after the row went
      File.write!(Uploads.absolute(String.replace(relative, ".mp4", ".web.mp4")), "film")

      :ok = Uploads.remove_upload(relative)

      refute File.exists?(Uploads.absolute(String.replace(relative, ".mp4", ".web.mp4")))
    end

    test "a half written file of a stopped server is swept" do
      stored(video_file(320, 240))
      partial = Uploads.absolute("videos/.tmp-99-something.web.mp4")
      File.write!(partial, "half")
      File.touch!(partial, System.os_time(:second) - 3600)

      :ok = Videos.sweep_partials()

      refute File.exists?(partial)
    end

    test "a half written file that is still being written stays" do
      stored(video_file(320, 240))
      partial = Uploads.absolute("videos/.tmp-98-underway.web.mp4")
      File.write!(partial, "half")

      :ok = Videos.sweep_partials()

      # a queue that comes back while the run before it still converts
      # must not take the file out from under that ffmpeg
      assert File.exists?(partial)
    end
  end

  describe "removing" do
    test "takes the derived files and the row with it" do
      relative = stored(video_file(320, 240))
      {:ok, video} = Videos.convert(Videos.ensure(relative))

      :ok = Uploads.remove_upload(relative)

      refute File.exists?(Uploads.absolute(relative))
      refute File.exists?(Uploads.absolute(video.mp4_path))
      refute File.exists?(Uploads.absolute(video.poster_path))
      assert Videos.get(relative) == nil
    end
  end
end
