defmodule Texttile.VideoFixtures do
  @moduledoc """
  Short test videos, made by ffmpeg itself. The feature needs ffmpeg
  anyway (`make tools`), so the fixtures come from the same tool
  instead of riding along as binaries in the repository.
  """

  @doc """
  Writes a one second test video of the given size and answers its
  path. `seconds` and `extension` let a test ask for a longer clip or
  another container.
  """
  def video_file(width \\ 640, height \\ 480, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 1)
    extension = Keyword.get(opts, :extension, ".mp4")
    path = Path.join(System.tmp_dir!(), "clip-#{System.unique_integer([:positive])}#{extension}")

    {_out, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-nostdin",
          "-hide_banner",
          "-loglevel",
          "error",
          "-y",
          "-f",
          "lavfi",
          "-i",
          "testsrc=size=#{width}x#{height}:rate=10:duration=#{seconds}",
          "-pix_fmt",
          "yuv420p",
          "-threads",
          "1",
          path
        ],
        stderr_to_stdout: true
      )

    path
  end

  @doc "A file that ends in .mp4 and holds no video at all."
  def broken_video_file do
    path = Path.join(System.tmp_dir!(), "broken-#{System.unique_integer([:positive])}.mp4")
    File.write!(path, "not a video")
    path
  end
end
