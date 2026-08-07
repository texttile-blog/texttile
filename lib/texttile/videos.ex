defmodule Texttile.Videos do
  @moduledoc """
  Self hosted video. An upload is kept exactly as it came, like every
  picture; what a page plays is one derived file, an MP4 that every
  browser reads, plus a poster frame beside it.

      videos/holiday-2f9c.mov        the original
      videos/holiday-2f9c.web.mp4    what the page plays
      videos/holiday-2f9c.poster.jpg the still the page shows first

  ffmpeg does the work, and it does it gently: one thread, the lowest
  scheduling priority, and idle IO where the kernel offers it. A
  conversion may take minutes; the site must stay quick while it runs.
  One video is converted at a time (`Texttile.Videos.Queue`).

  The setting Videos > Longest edge caps the size of the derived file.
  It applies to what is converted after the change; a video already
  converted keeps the file it has.
  """

  import Ecto.Query

  alias Texttile.Repo
  alias Texttile.Settings
  alias Texttile.Uploads
  alias Texttile.Videos.Video

  @topic "videos"

  # What a camera, a phone and a screen recorder hand over.
  @extensions ~w(.mp4 .mov .m4v .webm .avi .mkv)

  @doc "The upload extensions a video may arrive in."
  def extensions, do: @extensions

  @doc "Whether this name is a video by its extension."
  def video?(name) do
    name |> to_string() |> Path.extname() |> String.downcase() |> then(&(&1 in @extensions))
  end

  ## The row

  @doc """
  The row of a stored original, made on the first ask and answered
  from then on. It does not start the conversion; `queue/1` does.
  """
  def ensure(relative) do
    case get(relative) do
      nil ->
        Repo.insert!(%Video{path: relative, state: "queued"},
          on_conflict: :nothing,
          conflict_target: :path
        )

        get(relative)

      video ->
        video
    end
  end

  @doc "Puts a stored original in line for the conversion."
  def queue(relative) do
    video = ensure(relative)
    Texttile.Videos.Queue.push(relative)
    video
  end

  @doc "The row behind a stored original, or nil."
  def get(relative), do: Repo.one(from v in Video, where: v.path == ^relative)

  @doc """
  How far the conversion of one original has got: `:queued`,
  `:running`, `:done`, `:failed`, or `:none` for a path nobody
  uploaded.
  """
  def state(relative) do
    case get(relative) do
      nil -> :none
      %Video{state: "queued"} -> :queued
      %Video{state: "running"} -> :running
      %Video{state: "done"} -> :done
      %Video{state: "failed"} -> :failed
    end
  end

  @doc """
  What a page needs to play one video, or nil while the conversion is
  not through. Paths are relative to the uploads root.
  """
  def playback(relative) do
    case get(relative) do
      %Video{state: "done"} = video ->
        %{
          mp4: video.mp4_path,
          poster: video.poster_path,
          width: video.width,
          height: video.height,
          duration_ms: video.duration_ms
        }

      _ ->
        nil
    end
  end

  @doc "The poster of a converted video, or nil."
  def poster(relative) do
    case get(relative) do
      %Video{state: "done"} = video -> video.poster_path
      _ -> nil
    end
  end

  @doc """
  The picture that stands for a stored file: a picture stands for
  itself, a video for its poster, and a video that is not converted
  yet for nothing at all. Every tile, thumbnail and preview asks this.
  """
  def still(relative) do
    if video?(relative), do: poster(relative), else: relative
  end

  @doc """
  The videos among the given original paths, as `%{path => row}`. One
  query for a whole gallery or a whole text.
  """
  def by_path(relatives) do
    case Enum.filter(relatives, &video?/1) do
      # a text without a video asks the database nothing
      [] ->
        %{}

      paths ->
        Video
        |> where([v], v.path in ^paths)
        |> Repo.all()
        |> Map.new(&{&1.path, &1})
    end
  end

  @doc """
  What a whole gallery or a whole text has to show, in one query:
  `%{path => %{still:, film:, state:, error:}}`. A picture is its own
  still and has the state `:image`; a video has a still once ffmpeg is
  through, and says where it stands until then.
  """
  def stills(relatives) do
    rows = by_path(relatives)
    Map.new(relatives, &{&1, still_of(&1, rows[&1])})
  end

  defp still_of(relative, nil) do
    if video?(relative) do
      %{still: nil, film: nil, state: :none, error: nil}
    else
      %{still: relative, film: nil, state: :image, error: nil}
    end
  end

  defp still_of(_relative, %Video{state: "done"} = video) do
    %{still: video.poster_path, film: video.mp4_path, state: :done, error: nil}
  end

  defp still_of(_relative, %Video{} = video) do
    %{still: nil, film: nil, state: state_name(video.state), error: video.error}
  end

  defp state_name("queued"), do: :queued
  defp state_name("running"), do: :running
  defp state_name("failed"), do: :failed

  @doc "Every video still waiting, oldest first. The queue asks on boot."
  def unfinished do
    Video
    |> where([v], v.state in ["queued", "running"])
    |> order_by([v], asc: v.id)
    |> Repo.all()
  end

  @doc """
  Drops one video: the derived files go, then the row. The original is
  the caller's (see `Texttile.Uploads.remove_upload/1`).
  """
  def forget(relative) do
    case get(relative) do
      nil ->
        :ok

      video ->
        for path <- [video.mp4_path, video.poster_path], is_binary(path) do
          File.rm(Uploads.absolute(path))
          Texttile.Images.drop_renditions(path)
        end

        Repo.delete_all(from v in Video, where: v.id == ^video.id)
        :ok
    end
  end

  @doc """
  Marks a video failed from the outside, for the queue when the work
  died without a word of its own.
  """
  def give_up(nil, _reason), do: :ok

  def give_up(relative, reason) do
    case get(relative) do
      nil ->
        :ok

      video ->
        fail(video, reason)
        broadcast(relative)
        :ok
    end
  end

  ## The conversion

  @doc """
  Converts one stored original into the file a page plays and the
  poster beside it. Answers `{:ok, video}` or `{:error, video}`; the
  row carries the reason in either case.

  Both files are written under a name of their own and renamed, so a
  reader never meets a half made file.
  """
  def convert(%Video{} = video) do
    video = mark(video, "running")
    original = Uploads.absolute(video.path)
    max_edge = Settings.get(:video_max_edge)

    mp4 = derived(video.path, ".web.mp4")
    poster = derived(video.path, ".poster.jpg")
    partial_mp4 = partial(mp4)
    partial_poster = partial(poster)

    File.mkdir_p!(Path.dirname(Uploads.absolute(mp4)))

    result =
      with :ok <- ensure_readable(original),
           :ok <- run(encode_command(original, Uploads.absolute(partial_mp4), max_edge)),
           :ok <-
             run(poster_command(Uploads.absolute(partial_mp4), Uploads.absolute(partial_poster))),
           {:ok, probed} <- probe(Uploads.absolute(partial_mp4)),
           :ok <- File.rename(Uploads.absolute(partial_mp4), Uploads.absolute(mp4)),
           :ok <- File.rename(Uploads.absolute(partial_poster), Uploads.absolute(poster)) do
        {:ok, finish(video, mp4, poster, probed)}
      else
        {:error, reason} ->
          File.rm(Uploads.absolute(partial_mp4))
          File.rm(Uploads.absolute(partial_poster))
          {:error, fail(video, reason)}
      end

    broadcast(video.path)
    result
  end

  defp ensure_readable(original) do
    if File.regular?(original), do: :ok, else: {:error, "the file is gone"}
  end

  @doc """
  The ffmpeg call that makes the playable file: one MP4, H.264 and
  AAC, the longer edge within `max_edge` and never scaled up, the
  index at the front so a browser can start before the file is there.

  It runs on one thread and at the lowest priority the machine
  offers. A conversion is never the most important thing on this
  server; answering a reader is.
  """
  def encode_command(input, output, max_edge) do
    gentle([
      "ffmpeg",
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-i",
      input,
      "-vf",
      scale_filter(max_edge),
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-crf",
      "23",
      "-pix_fmt",
      "yuv420p",
      "-threads",
      "1",
      "-c:a",
      "aac",
      "-b:a",
      "128k",
      "-movflags",
      "+faststart",
      output
    ])
  end

  @doc "The ffmpeg call that takes the poster out of the converted file."
  def poster_command(input, output) do
    gentle([
      "ffmpeg",
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      "0.5",
      "-i",
      input,
      "-frames:v",
      "1",
      "-q:v",
      "3",
      "-threads",
      "1",
      output
    ])
  end

  # Fit inside a max_edge square, shrinking only, and land on even
  # numbers, which is what H.264 with yuv420p needs. The quotes are
  # ffmpeg's own: they keep the comma inside min() from reading as the
  # start of the next filter.
  defp scale_filter(max_edge) do
    "scale=w='min(#{max_edge},iw)':h='min(#{max_edge},ih)'" <>
      ":force_original_aspect_ratio=decrease:force_divisible_by=2"
  end

  # The lowest scheduling priority, and idle IO where the kernel has
  # it. Without either tool the command still runs, only louder.
  defp gentle([tool | args]) do
    cond do
      ionice = System.find_executable("ionice") ->
        {ionice, ["-c", "3", "nice", "-n", "19", tool | args]}

      nice = System.find_executable("nice") ->
        {nice, ["-n", "19", tool | args]}

      true ->
        {tool, args}
    end
  end

  defp run({command, args}) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, reason_from(output)}
    end
  rescue
    error in ErlangError ->
      case error do
        %ErlangError{original: :enoent} -> {:error, "ffmpeg is not installed"}
        _ -> {:error, "ffmpeg could not be started"}
      end
  end

  # ffmpeg says a lot; the row keeps the last line it wrote, which is
  # the one that names the trouble.
  defp reason_from(output) do
    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> to_string()
    |> String.trim()
    |> String.slice(0, 200)
    |> case do
      "" -> "the file could not be converted"
      line -> line
    end
  end

  # The size the reader will see, read off the finished file, so no
  # rotation flag has to be understood here.
  defp probe(path) do
    args = [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=width,height",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1",
      path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        fields =
          output
          |> String.split("\n", trim: true)
          |> Map.new(fn line ->
            [key, value] = String.split(line, "=", parts: 2)
            {key, value}
          end)

        with {:ok, width} <- integer(fields["width"]),
             {:ok, height} <- integer(fields["height"]) do
          {:ok, %{width: width, height: height, duration_ms: milliseconds(fields["duration"])}}
        else
          _ -> {:error, "the converted file has no picture"}
        end

      {output, _code} ->
        {:error, reason_from(output)}
    end
  rescue
    ErlangError -> {:error, "ffprobe is not installed"}
  end

  defp integer(nil), do: :error

  defp integer(value) do
    case Integer.parse(value) do
      {number, _rest} -> {:ok, number}
      :error -> :error
    end
  end

  defp milliseconds(nil), do: nil

  defp milliseconds(value) do
    case Float.parse(value) do
      {seconds, _rest} -> round(seconds * 1000)
      :error -> nil
    end
  end

  ## Names

  # The derived files stand beside the original and carry its name, so
  # one look at the directory says what belongs to what.
  defp derived(relative, suffix), do: Path.rootname(relative) <> suffix

  defp partial(relative) do
    Path.join(
      Path.dirname(relative),
      ".tmp-#{System.unique_integer([:positive])}-" <> Path.basename(relative)
    )
  end

  ## The row's story

  defp mark(video, state) do
    video
    |> Ecto.Changeset.change(state: state)
    |> Repo.update!()
    |> tap(fn video -> broadcast(video.path) end)
  end

  defp finish(video, mp4, poster, probed) do
    video
    |> Ecto.Changeset.change(
      state: "done",
      error: nil,
      mp4_path: mp4,
      poster_path: poster,
      width: probed.width,
      height: probed.height,
      duration_ms: probed.duration_ms
    )
    |> Repo.update!()
  end

  defp fail(video, reason) do
    video
    |> Ecto.Changeset.change(state: "failed", error: to_string(reason))
    |> Repo.update!()
  end

  ## PubSub

  @doc "Subscribes the caller to `{:video_changed, path}` messages."
  def subscribe do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)
  end

  defp broadcast(path) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:video_changed, path})
  end
end
