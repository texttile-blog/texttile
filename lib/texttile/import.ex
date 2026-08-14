defmodule Texttile.Import do
  @moduledoc """
  The import of bundles, in the two steps IMPORT.md promises: `validate`
  reads every bundle and answers the dry-run report, nothing written;
  `run` turns the report's healthy bundles into texts, one after the
  other - SQLite has one writer, and a migration has time. Each bundle
  lands in one transaction: a surprise mid-bundle rolls the text back
  whole and fails that bundle alone.

  Remote pictures travel here, not in the zip: the dry run asks every
  URL (HEAD first, a one-byte GET when the host refuses HEAD), the run
  downloads the bytes. The fetches are guarded: no private addresses,
  no redirects, a size cap per picture, and caps on what the zip may
  unpack to. Everything goes through `:import_req_options`, which the
  tests point at a stub.
  """

  import Bitwise

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Body
  alias Texttile.Articles.Lock
  alias Texttile.Comments
  alias Texttile.Gallery
  alias Texttile.Import.Bundle
  alias Texttile.Repo
  alias Texttile.Uploads
  alias Texttile.Videos

  defmodule Report do
    @moduledoc "What the dry run found: the bundles, judged, and the whole-zip notes."
    defstruct bundles: [], warnings: [], hosts: []
  end

  ## Unpacking

  @doc """
  The folder the import works in. The zip lands here and unpacks here,
  and it is the machine's temporary folder, not the volume the uploads
  lie on. On a server those are two disks of two sizes, and this is
  the one that says whether a zip can be unpacked at all.
  """
  def workroom, do: System.tmp_dir!()

  @doc """
  Whether `bytes` fit in the `free` bytes where they would land, and
  the two numbers in words when they do not.

  A system that will not say what is free answers nil, and nil refuses
  nothing: the unpacking then fails on the disk, with the reason the
  disk gives. A guess must not stop an import that would have run.
  """
  def room_for(_bytes, nil), do: :ok

  def room_for(bytes, free) when bytes > free do
    {:error,
     "the zip unpacks to #{mb(bytes)}, and #{mb(free)} is free where the import works; " <>
       "use a smaller zip or make room on the server"}
  end

  def room_for(_bytes, _free), do: :ok

  @doc """
  Takes the finished upload out of LiveView's temporary file, under a
  name of our own, and answers where it now lies. LiveView removes its
  file the moment the upload is consumed, so the zip has to leave it.

  Renaming is one line in a folder, whatever the file weighs; copying
  is not. A 1.6 GB zip held the import page for 84 seconds here, long
  enough for the upload channel to die under it, and asked `/tmp` for
  the archive twice over. Both files lie in the workroom, so the
  rename is a rename. A source somewhere else cannot be renamed, and
  that case still copies.
  """
  def keep_upload(source_path) do
    kept =
      Path.join(workroom(), "texttile-upload-#{System.unique_integer([:positive])}.zip")

    case File.rename(source_path, kept) do
      :ok ->
        kept

      {:error, _reason} ->
        File.cp!(source_path, kept)
        File.rm(source_path)
        kept
    end
  end

  @doc """
  Unpacks the uploaded zip into `dest` and answers the zip-level
  warnings. The entry list is judged first: a name that would land
  outside `dest`, too many entries, too large an unpacked size, or
  more than the disk behind `dest` still holds refuses the whole
  archive.
  """
  def unpack(zip_path, dest) do
    with {:ok, entries} <- list_entries(zip_path),
         :ok <- safe(entries),
         :ok <- within_limits(entries),
         :ok <- room_for(unpacked_bytes(entries), Uploads.free_bytes(dest)) do
      case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(dest)) do
        {:ok, _files} -> {:ok, zip_warnings(dest)}
        {:error, reason} -> {:error, "the zip did not unpack (#{inspect(reason)})"}
      end
    end
  end

  defp list_entries(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, entries} ->
        {:ok,
         for {:zip_file, name, info, _comment, _offset, _comp_size} <- entries do
           size = elem(info, 1)
           {to_string(name), if(is_integer(size), do: size, else: 0)}
         end}

      {:error, reason} ->
        {:error, "this is not a zip archive (#{inspect(reason)})"}
    end
  end

  defp safe(entries) do
    case Enum.find(entries, fn {name, _size} ->
           Path.type(name) != :relative or ".." in Path.split(name)
         end) do
      nil -> :ok
      {bad, _size} -> {:error, "the archive entry #{bad} would land outside the archive"}
    end
  end

  # A zip is small; what it unpacks to need not be. These caps keep a
  # decompression bomb from filling the volume the database lives on.
  defp within_limits(entries) do
    {max_entries, max_bytes} =
      Application.get_env(:texttile, :import_zip_limits, {20_000, 4_294_967_296})

    bytes = unpacked_bytes(entries)

    cond do
      length(entries) > max_entries ->
        {:error, "the zip holds #{length(entries)} entries; the cap is #{max_entries}"}

      bytes > max_bytes ->
        {:error, "the zip unpacks to #{mb(bytes)}; the cap is #{mb(max_bytes)}"}

      true ->
        :ok
    end
  end

  defp unpacked_bytes(entries), do: entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()

  defp mb(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp zip_warnings(dir) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      cond do
        File.regular?(Path.join(dir, name)) ->
          ["#{name} sits at the zip root; a bundle is a folder"]

        File.ls!(Path.join(dir, name)) == [] ->
          ["the folder #{name} is empty"]

        true ->
          []
      end
    end)
  end

  ## The dry run

  @doc """
  Reads every bundle folder below `dir` and answers the report: the
  bundles with their complaints, the zip-level warnings, and the hosts
  the import would download from. `progress` hears what is being
  checked: `{:checking_url, url, index, total}` and
  `{:retrying, url, what}`.
  """
  def validate(dir, progress \\ fn _event -> :ok end) do
    bundles =
      dir
      |> bundle_dirs()
      |> Enum.map(&Bundle.read/1)
      |> oldest_first()
      |> mark_duplicate_slugs()
      |> mark_existing_slugs()

    {bundles, hosts} = check_urls(bundles, progress)

    %Report{bundles: bundles, warnings: zip_warnings(dir), hosts: hosts}
  end

  defp bundle_dirs(dir) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.filter(fn path -> File.dir?(path) and File.ls!(path) != [] end)
  end

  # The order of the report is the order of the run: oldest text first,
  # the way an archive was written. A bundle without a date has nothing
  # to sort by and goes last, under its folder name.
  defp oldest_first(bundles) do
    Enum.sort_by(bundles, fn bundle ->
      case bundle.date do
        %Date{} = date -> {0, Date.to_erl(date), bundle.name}
        _ -> {1, {0, 0, 0}, bundle.name}
      end
    end)
  end

  defp mark_duplicate_slugs(bundles) do
    taken_twice =
      bundles
      |> Enum.map(& &1.slug)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_slug, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    Enum.map(bundles, fn bundle ->
      if bundle.slug in taken_twice do
        complain(bundle, "the slug #{bundle.slug} appears in more than one bundle")
      else
        bundle
      end
    end)
  end

  defp mark_existing_slugs(bundles) do
    Enum.map(bundles, fn bundle ->
      case bundle.slug && Repo.get_by(Article, slug: bundle.slug) do
        nil ->
          bundle

        article ->
          bundle =
            warn(bundle, "the slug #{bundle.slug} already exists; the import updates that text")

          if Lock.state(article.id) == :free do
            bundle
          else
            warn(
              bundle,
              "the text /#{bundle.slug} is open in an editor; the run refuses it while it stays open"
            )
          end
      end
    end)
  end

  # Every URL once, however many bundles share it.
  defp check_urls(bundles, progress) do
    urls =
      bundles
      |> Enum.flat_map(&Bundle.sources/1)
      |> Enum.filter(&Bundle.url?/1)
      |> Enum.uniq()

    total = length(urls)

    verdicts =
      urls
      |> Enum.with_index(1)
      |> Map.new(fn {url, index} ->
        progress.({:checking_url, url, index, total})
        {url, head_check(url, progress)}
      end)

    bundles =
      Enum.map(bundles, fn bundle ->
        bundle
        |> Bundle.sources()
        |> Enum.flat_map(fn source ->
          case verdicts[source] do
            {:error, message} -> [message]
            _ -> []
          end
        end)
        |> Enum.reduce(bundle, &complain(&2, &1))
      end)

    hosts = urls |> Enum.map(&URI.parse(&1).host) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {bundles, hosts}
  end

  defp head_check(url, progress) do
    with :ok <- host_check(url) do
      case request(method: :head, url: url, retry: noted_retry(progress, url)) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          picture_answer(url, response)

        {:ok, %Req.Response{status: status} = response} when status in 300..399 ->
          redirect_error(url, response)

        # Some hosts refuse HEAD outright; a one-byte GET asks again.
        _refused ->
          case request(
                 method: :get,
                 url: url,
                 headers: [range: "bytes=0-0"],
                 decode_body: false,
                 retry: noted_retry(progress, url)
               ) do
            {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
              picture_answer(url, response)

            {:ok, %Req.Response{status: status} = response} when status in 300..399 ->
              redirect_error(url, response)

            other ->
              req_failure(url, other)
          end
      end
    end
  end

  defp picture_answer(url, response) do
    type = content_type(response)

    cond do
      not String.starts_with?(type, "image/") ->
        {:error, "#{url} answers with #{type}, not a picture"}

      declared_size(response) > max_picture_bytes() ->
        {:error, "#{url} is larger than the #{mb(max_picture_bytes())} cap"}

      true ->
        :ok
    end
  end

  # The size the host announces: the total of a content-range answer
  # (the ranged GET), or the content-length (a HEAD). Absent means 0;
  # the run's own cap still stands either way.
  defp declared_size(response) do
    with [range | _] <- Req.Response.get_header(response, "content-range"),
         [_, total] <- Regex.run(~r{/(\d+)\z}, range) do
      String.to_integer(total)
    else
      _ ->
        case Req.Response.get_header(response, "content-length") do
          [length | _] ->
            case Integer.parse(length) do
              {bytes, _rest} -> bytes
              :error -> 0
            end

          [] ->
            0
        end
    end
  end

  defp redirect_error(url, response) do
    where =
      case Req.Response.get_header(response, "location") do
        [location | _] -> " to #{location}"
        [] -> ""
      end

    {:error, "#{url} redirects#{where}; use the final address"}
  end

  defp req_failure(url, {:ok, %Req.Response{status: status}}),
    do: {:error, "#{url} answers #{status}"}

  defp req_failure(url, {:error, error}),
    do: {:error, "#{url} is not reachable (#{Exception.message(error)})"}

  # Redirects stay off on purpose: the host list in the report is a
  # promise about where the import will reach, and a redirect would
  # break it. The final address belongs in the bundle.
  defp request(options) do
    Req.request(options ++ [redirect: false] ++ req_options())
  end

  # Req's own transient set, spelled out so the page can say what is
  # happening instead of a server-log line saying it alone.
  defp noted_retry(note, url) do
    fn _request, answer ->
      case answer do
        %Req.Response{status: status} when status in [408, 429, 500, 502, 503, 504] ->
          note.({:retrying, url, "answers #{status}"})
          true

        %Req.Response{} ->
          false

        exception when is_exception(exception) ->
          note.({:retrying, url, "is not reachable (#{Exception.message(exception)})"})
          true
      end
    end
  end

  defp content_type(response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first()
    |> to_string()
    |> String.split(";")
    |> List.first()
  end

  defp req_options do
    Application.get_env(:texttile, :import_req_options, [])
  end

  defp max_picture_bytes do
    Application.get_env(:texttile, :import_max_picture_bytes, 104_857_600)
  end

  defp receive_timeout do
    Application.get_env(:texttile, :import_receive_timeout, 300_000)
  end

  # The importer is the one place this server fetches foreign URLs, and
  # bundles are machine-made from someone else's export. Loopback and
  # the private ranges stay out of reach, so a crafted bundle cannot
  # read the deployment's insides. Dev and the tests say yes to them.
  defp host_check(url) do
    if Application.get_env(:texttile, :import_allow_private_hosts, false) do
      :ok
    else
      host = URI.parse(url).host |> to_string() |> String.to_charlist()

      addresses =
        Enum.flat_map([:inet, :inet6], fn family ->
          case :inet.getaddr(host, family) do
            {:ok, address} -> [address]
            {:error, _} -> []
          end
        end)

      cond do
        addresses == [] ->
          {:error, "#{url}: the host does not resolve"}

        Enum.any?(addresses, &private_address?/1) ->
          {:error, "#{url} points into the private network"}

        true ->
          :ok
      end
    end
  end

  defp private_address?({a, b, _c, _d}) do
    a in [0, 10, 127] or
      (a == 100 and b in 64..127) or
      (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or
      (a == 192 and b == 168) or
      a >= 224
  end

  defp private_address?({0, 0, 0, 0, 0, 0xFFFF, x, y}) do
    private_address?({div(x, 256), rem(x, 256), div(y, 256), rem(y, 256)})
  end

  defp private_address?({a, _, _, _, _, _, _, _} = address) do
    address == {0, 0, 0, 0, 0, 0, 0, 0} or
      address == {0, 0, 0, 0, 0, 0, 0, 1} or
      band(a, 0xFE00) == 0xFC00 or
      band(a, 0xFFC0) == 0xFE80
  end

  ## The run

  @doc """
  Imports every bundle of the report that has no errors, one at a time.
  `progress` hears `{:bundle, name, index, total}` before each one,
  then `{:fetching, source, index, total}` per picture and
  `{:retrying, url, what}` when a host has to be asked again.
  Answers the summary: created, updated, skipped, and the failures.
  """
  def run(%Report{} = report, user, progress \\ fn _event -> :ok end, opts \\ []) do
    # `today:` names the day a bundle's date is judged against: a later
    # date schedules, its own day or an earlier one goes live.
    today = Keyword.get(opts, :today, Date.utc_today())
    importable = Enum.filter(report.bundles, &(&1.errors == []))
    total = length(importable)

    importable
    |> Enum.with_index(1)
    |> Enum.reduce(
      %{created: 0, updated: 0, skipped: length(report.bundles) - total, failed: []},
      fn {bundle, index}, summary ->
        progress.({:bundle, bundle.name, index, total})

        case import_bundle(bundle, user, progress, today) do
          {:ok, :created} -> %{summary | created: summary.created + 1}
          {:ok, :updated} -> %{summary | updated: summary.updated + 1}
          {:error, message} -> %{summary | failed: summary.failed ++ [{bundle.name, message}]}
        end
      end
    )
  end

  # The pictures go to disk first, the database work in one
  # transaction after: a bundle that dies halfway rolls its text back
  # whole and leaves only files to sweep, and those are swept here too.
  # The old files fall last, once the transaction holds - a rollback
  # must find them still in place.
  defp import_bundle(bundle, user, progress, today) do
    with :ok <- refuse_locked(bundle),
         {:ok, stored} <- store_pictures(bundle, progress) do
      try do
        {:ok, {verb, old_paths}} =
          Repo.transaction(fn -> apply_bundle(bundle, stored, user, today) end,
            timeout: :infinity
          )

        Enum.each(old_paths -- stored_paths(stored), &Uploads.remove_upload/1)
        {:ok, verb}
      rescue
        error ->
          Enum.each(stored_paths(stored), &Uploads.remove_upload/1)
          {:error, Exception.message(error)}
      end
    end
  end

  # The document lock is soft and lives with the editors; the import
  # honors it the same way they do. Checked before the downloads, so
  # nothing is fetched for a bundle that will be refused. A lock taken
  # while this very bundle runs still wins the race - the lock is a
  # courtesy, not a fence.
  defp refuse_locked(%Bundle{slug: slug}) do
    article = slug && Repo.get_by(Article, slug: slug)

    if article && Lock.state(article.id) != :free do
      {:error, "the text /#{slug} is open in an editor right now; close it and import again"}
    else
      :ok
    end
  end

  defp store_pictures(bundle, progress) do
    sources = Bundle.sources(bundle)
    total = length(sources)

    sources
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, fn {source, index}, {:ok, stored} ->
      progress.({:fetching, source, index, total})

      case store_picture(bundle, source, progress) do
        {:ok, picture} ->
          {:cont, {:ok, Map.put(stored, source, picture)}}

        {:error, message} ->
          Enum.each(stored_paths(stored), &Uploads.remove_upload/1)
          {:halt, {:error, message}}
      end
    end)
  end

  defp stored_paths(stored), do: stored |> Map.values() |> Enum.map(& &1.path)

  # A surprise here (a full disk, a body that will not read) fails the
  # one bundle, never the whole run: store_pictures hears {:error} and
  # rolls the bundle's files back.
  defp store_picture(bundle, source, progress) do
    cond do
      Bundle.url?(source) ->
        download(source, progress)

      # A film is stored as it came and stands in line for ffmpeg, the
      # way a film dropped into the editor does. The queue takes a path
      # once, so a film that is a tile and a reference in the words is
      # converted once.
      Videos.video?(source) ->
        with {:ok, relative} <-
               Uploads.put_body_video(Path.join(bundle.dir, source), Path.basename(source)) do
          Videos.queue(relative)
          {:ok, %{path: relative, name: Path.basename(source)}}
        end

      true ->
        with {:ok, relative} <-
               Uploads.put_body_image(Path.join(bundle.dir, source), Path.basename(source)) do
          {:ok, %{path: relative, name: Path.basename(source)}}
        end
    end
  rescue
    error -> {:error, "#{source}: #{Exception.message(error)}"}
  end

  @doc """
  Makes `path` usable as a fresh file: whatever stands there goes
  first. The zip extraction folders and the picture downloads share the
  system temp directory, and the name counter starts over with every
  boot, so a folder an earlier run left behind can carry the very name
  the next download draws.
  """
  def tmp_path(path) do
    File.rm_rf(path)
    path
  end

  defp download(url, progress) do
    with :ok <- host_check(url) do
      # a prefix of its own, so a download and an extraction folder
      # never draw from the same pool of names
      tmp =
        tmp_path(Path.join(workroom(), "texttile-fetch-#{System.unique_integer([:positive])}"))

      file = File.open!(tmp, [:write, :binary])
      cap = max_picture_bytes()

      # The body streams to disk, counted; a host that lied about its
      # size is stopped at the cap instead of filling the memory.
      into = fn {:data, chunk}, {request, response} ->
        seen = Map.get(response.private, :texttile_bytes)

        # The first chunk of an attempt starts the file over: Req
        # retries a failed request, and attempt two must not append to
        # what attempt one left behind.
        if seen == nil do
          {:ok, 0} = :file.position(file, :bof)
          :ok = :file.truncate(file)
        end

        # An error page's body (a 502 from a struggling host) is not
        # the picture; the status judges the attempt, not the file.
        if response.status in 200..299 do
          IO.binwrite(file, chunk)
        end

        seen = (seen || 0) + byte_size(chunk)
        response = put_in(response.private[:texttile_bytes], seen)

        if seen > cap do
          {:halt, {request, response}}
        else
          {:cont, {request, response}}
        end
      end

      # A big picture from slow hosting takes its time; the default
      # fifteen seconds of idle patience are for API calls, not bodies.
      result =
        request(
          method: :get,
          url: url,
          into: into,
          receive_timeout: receive_timeout(),
          retry: noted_retry(progress, url)
        )

      File.close(file)

      stored =
        case result do
          {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
            cond do
              Map.get(response.private, :texttile_bytes, 0) > cap ->
                {:error, "#{url} is larger than the #{mb(cap)} cap"}

              true ->
                name = remote_name(url, response)

                case Uploads.put_body_image(tmp, name) do
                  {:ok, relative} -> {:ok, %{path: relative, name: name}}
                  {:error, message} -> {:error, "#{url}: #{message}"}
                end
            end

          {:ok, %Req.Response{status: status} = response} when status in 300..399 ->
            redirect_error(url, response)

          other ->
            req_failure(url, other)
        end

      File.rm(tmp)
      stored
    end
  end

  @extension_for %{
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/webp" => ".webp",
    "image/gif" => ".gif"
  }

  # The name the upload goes by: the URL's own file name when it carries
  # a picture extension, otherwise the name mended with the extension
  # the content type names.
  defp remote_name(url, response) do
    base = url |> URI.parse() |> Map.get(:path) |> to_string() |> Path.basename()

    if String.downcase(Path.extname(base)) in Bundle.picture_extensions() do
      base
    else
      extension = Map.get(@extension_for, content_type(response), ".jpg")
      root = if base == "", do: "picture", else: Path.rootname(base)
      root <> extension
    end
  end

  ## One bundle into one text

  # Runs inside the transaction; every complaint raises, and the raise
  # rolls the whole bundle back. Answers {verb, old_paths}: the files
  # the text owned before, for the caller to remove once the commit
  # holds.
  defp apply_bundle(bundle, stored, user, today) do
    existing = Repo.get_by(Article, slug: bundle.slug)

    {verb, article} =
      case existing do
        nil ->
          {:ok, article} = Articles.create_draft(user)
          {:created, article}

        article ->
          # The words before the update stay restorable as a version.
          # Its pictures follow the app's one rule for versions: they
          # never guard a file (see Articles.delete_article).
          Articles.snapshot(article, user)
          {:updated, article}
      end

    old_paths = if existing, do: old_picture_paths(article), else: []

    {:ok, article} =
      Articles.update_text(article, %{
        title: bundle.title,
        body: rewrite_body(bundle.body, stored)
      })

    {:ok, article} =
      Articles.update_settings(article, %{
        type: bundle.type,
        tags: Enum.join(bundle.tags, ", "),
        slug: bundle.slug,
        allow_comments: bundle.allow_comments,
        preview_path: bundle.preview && stored[bundle.preview].path
      })

    article = set_state(article, bundle, user, today)
    replace_gallery(article, bundle, stored, today)
    Comments.replace_imported(article, bundle.comments)

    Articles.push_log(article, user, "imported the text from a bundle")
    {verb, old_paths}
  end

  # What the text owned before the update: its tiles and the uploads
  # its body speaks of. The bundle re-uploads everything it kept, so
  # after the update these files belong to nobody.
  defp old_picture_paths(article) do
    Enum.uniq(Gallery.paths(article.id) ++ Body.upload_paths(article.body))
  end

  defp rewrite_body(body, stored) do
    Body.rewrite(body, fn whole, alt, url ->
      case stored[String.trim(url)] do
        nil -> whole
        %{path: relative} -> "![#{alt}](/uploads/#{relative})"
      end
    end)
  end

  defp set_state(article, %Bundle{status: "draft"} = bundle, user, today) do
    article =
      if article.status == "draft" do
        article
      else
        {:ok, article} = Articles.unpublish(article, user)
        article
      end

    case bundle.date do
      nil ->
        article

      date ->
        {:ok, article} = Articles.set_publish_date(article, user, date, today: today)
        article
    end
  end

  defp set_state(article, %Bundle{status: "published"} = bundle, user, today) do
    date = bundle.date || today

    # The stamp goes on before the text goes live, because going live
    # is what sends the mail: an already published import never mails
    # the subscribers after the fact. A future date is a scheduled
    # text and keeps no stamp; it goes live on its day like any other,
    # notification included. IMPORT.md says so.
    article = mark_notified(article, date, today)

    {:ok, article} = Articles.set_publish_date(article, user, date, today: today)

    if article.status == "draft" do
      {:ok, article} = Articles.publish(article, user, today: today)
      article
    else
      article
    end
  end

  defp mark_notified(article, date, today) do
    if Date.compare(date, today) == :gt do
      article
    else
      article
      |> Article.state_changeset(%{notified_on: date})
      |> Repo.update!()
    end
  end

  defp replace_gallery(article, bundle, stored, today) do
    base = DateTime.new!(article.publish_date || today, ~T[12:00:00.000000], "Etc/UTC")

    tiles =
      bundle.gallery
      |> Enum.with_index()
      |> Enum.map(fn {source, index} ->
        %{path: path, name: name} = stored[source]
        {path, name, DateTime.add(base, index, :second)}
      end)

    Gallery.replace_imported(article, tiles)
  end

  defp complain(bundle, message), do: %{bundle | errors: bundle.errors ++ [message]}
  defp warn(bundle, message), do: %{bundle | warnings: bundle.warnings ++ [message]}
end
