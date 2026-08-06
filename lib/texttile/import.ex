defmodule Texttile.Import do
  @moduledoc """
  The import of bundles, in the two steps IMPORT.md promises: `validate`
  reads every bundle and answers the dry-run report, nothing written;
  `run` turns the report's healthy bundles into texts, one after the
  other - SQLite has one writer, and a migration has time.

  Remote pictures travel here, not in the zip: the dry run asks every
  URL with a HEAD request, the run downloads the bytes. Both go through
  `:import_req_options`, which the tests point at a stub.
  """

  import Ecto.Query

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Gallery
  alias Texttile.Import.Bundle
  alias Texttile.Repo
  alias Texttile.Uploads

  defmodule Report do
    @moduledoc "What the dry run found: the bundles, judged, and the whole-zip notes."
    defstruct dir: nil, bundles: [], warnings: [], hosts: []
  end

  ## Unpacking

  @doc """
  Unpacks the uploaded zip into `dest` and answers the zip-level
  warnings. Entry names are checked first; an entry that would land
  outside `dest` refuses the whole archive.
  """
  def unpack(zip_path, dest) do
    with {:ok, names} <- entry_names(zip_path),
         :ok <- safe(names) do
      case :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(dest)) do
        {:ok, _files} -> {:ok, zip_warnings(dest)}
        {:error, reason} -> {:error, "the zip did not unpack (#{inspect(reason)})"}
      end
    end
  end

  defp entry_names(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, entries} ->
        {:ok, for({:zip_file, name, _info, _comment, _offset, _size} <- entries, do: to_string(name))}

      {:error, reason} ->
        {:error, "this is not a zip archive (#{inspect(reason)})"}
    end
  end

  defp safe(names) do
    case Enum.find(names, &(Path.type(&1) != :relative or ".." in Path.split(&1))) do
      nil -> :ok
      bad -> {:error, "the archive entry #{bad} would land outside the archive"}
    end
  end

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
  the import would download from.
  """
  def validate(dir) do
    bundles =
      dir
      |> bundle_dirs()
      |> Enum.map(&Bundle.read/1)
      |> mark_duplicate_slugs()
      |> mark_existing_slugs()

    {bundles, hosts} = check_urls(bundles)

    %Report{dir: dir, bundles: bundles, warnings: zip_warnings(dir), hosts: hosts}
  end

  defp bundle_dirs(dir) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.filter(fn path -> File.dir?(path) and File.ls!(path) != [] end)
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
      if bundle.slug && Repo.exists?(from a in Article, where: a.slug == ^bundle.slug) do
        warn(bundle, "the slug #{bundle.slug} already exists; the import updates that text")
      else
        bundle
      end
    end)
  end

  # Every URL once, however many bundles share it.
  defp check_urls(bundles) do
    urls =
      bundles
      |> Enum.flat_map(&Bundle.sources/1)
      |> Enum.filter(&Bundle.url?/1)
      |> Enum.uniq()

    verdicts = Map.new(urls, fn url -> {url, head_check(url)} end)

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

  defp head_check(url) do
    case Req.request([method: :head, url: url] ++ req_options()) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        type = content_type(response)

        if String.starts_with?(type, "image/") do
          :ok
        else
          {:error, "#{url} answers with #{type}, not a picture"}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "#{url} answers #{status}"}

      {:error, error} ->
        {:error, "#{url} is not reachable (#{Exception.message(error)})"}
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

  ## The run

  @doc """
  Imports every bundle of the report that has no errors, one at a time.
  `progress` hears `{:bundle, name, index, total}` before each one.
  Answers the summary: created, updated, skipped, and the failures.
  """
  def run(%Report{} = report, user, progress \\ fn _event -> :ok end) do
    importable = Enum.filter(report.bundles, &(&1.errors == []))
    total = length(importable)

    importable
    |> Enum.with_index(1)
    |> Enum.reduce(
      %{created: 0, updated: 0, skipped: length(report.bundles) - total, failed: []},
      fn {bundle, index}, summary ->
        progress.({:bundle, bundle.name, index, total})

        case import_bundle(bundle, user) do
          {:ok, :created} -> %{summary | created: summary.created + 1}
          {:ok, :updated} -> %{summary | updated: summary.updated + 1}
          {:error, message} -> %{summary | failed: summary.failed ++ [{bundle.name, message}]}
        end
      end
    )
  end

  # The pictures go to disk first, the database after: a bundle that
  # dies halfway leaves no half-imported text, only files to sweep,
  # and those are swept here too.
  defp import_bundle(bundle, user) do
    with {:ok, stored} <- store_pictures(bundle) do
      try do
        {:ok, apply_bundle(bundle, stored, user)}
      rescue
        error ->
          Enum.each(Map.values(stored), &Uploads.remove_body_image/1)
          {:error, Exception.message(error)}
      end
    end
  end

  defp store_pictures(bundle) do
    bundle
    |> Bundle.sources()
    |> Enum.reduce_while({:ok, %{}}, fn source, {:ok, stored} ->
      case store_picture(bundle, source) do
        {:ok, relative} ->
          {:cont, {:ok, Map.put(stored, source, relative)}}

        {:error, message} ->
          Enum.each(Map.values(stored), &Uploads.remove_body_image/1)
          {:halt, {:error, message}}
      end
    end)
  end

  defp store_picture(bundle, source) do
    if Bundle.url?(source) do
      download(source)
    else
      Uploads.put_body_image(Path.join(bundle.dir, source), Path.basename(source))
    end
  end

  defp download(url) do
    case Req.request([method: :get, url: url] ++ req_options()) do
      {:ok, %Req.Response{status: status, body: body} = response} when status in 200..299 ->
        tmp = Path.join(System.tmp_dir!(), "texttile-import-#{System.unique_integer([:positive])}")
        File.write!(tmp, body)
        stored = Uploads.put_body_image(tmp, remote_name(url, response))
        File.rm(tmp)

        case stored do
          {:ok, relative} -> {:ok, relative}
          {:error, message} -> {:error, "#{url}: #{message}"}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "#{url} answers #{status}"}

      {:error, error} ->
        {:error, "#{url} is not reachable (#{Exception.message(error)})"}
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

  defp apply_bundle(bundle, stored, user) do
    existing = Repo.get_by(Article, slug: bundle.slug)

    {verb, article} =
      case existing do
        nil ->
          {:ok, article} = Articles.create_draft(user)
          {:created, article}

        article ->
          # the state before the update stays restorable
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
        preview_path: bundle.preview && stored[bundle.preview]
      })

    article = set_state(article, bundle, user)
    replace_gallery(article, bundle, stored)

    Enum.each(old_paths -- Map.values(stored), &Uploads.remove_body_image/1)

    Articles.push_log(article, user, "imported the text from a bundle")
    verb
  end

  # What the text owned before the update: its tiles and the uploads
  # its body speaks of. The bundle re-uploads everything it kept, so
  # after the update these files belong to nobody.
  defp old_picture_paths(article) do
    inline =
      article.body
      |> Articles.inline_refs()
      |> Enum.flat_map(fn
        %{kind: :done, url: "/uploads/" <> relative} -> [relative]
        _ -> []
      end)

    Enum.uniq(Gallery.paths(article.id) ++ inline)
  end

  defp rewrite_body(body, stored) do
    Regex.replace(~r/!\[([^\]]*)\]\(([^)]*)\)/, body, fn whole, alt, url ->
      case stored[String.trim(url)] do
        nil -> whole
        relative -> "![#{alt}](/uploads/#{relative})"
      end
    end)
  end

  defp set_state(article, %Bundle{status: "draft"} = bundle, user) do
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
        {:ok, article} = Articles.set_publish_date(article, user, date)
        article
    end
  end

  defp set_state(article, %Bundle{status: "published"} = bundle, user) do
    date = bundle.date || Date.utc_today()
    {:ok, article} = Articles.set_publish_date(article, user, date)

    article =
      if article.status == "draft" do
        {:ok, article} = Articles.publish(article, user)
        article
      else
        article
      end

    mark_notified(article)
  end

  # An imported text never mails the subscribers after the fact; it
  # counts as told about on its own publish day.
  defp mark_notified(%Article{status: "published"} = article) do
    article
    |> Article.state_changeset(%{notified_on: article.publish_date})
    |> Repo.update!()
  end

  defp mark_notified(article), do: article

  defp replace_gallery(article, bundle, stored) do
    Repo.delete_all(from i in Gallery.Image, where: i.article_id == ^article.id)

    base = DateTime.new!(article.publish_date || Date.utc_today(), ~T[12:00:00.000000], "Etc/UTC")

    bundle.gallery
    |> Enum.with_index()
    |> Enum.each(fn {source, index} ->
      {:ok, _image} =
        Gallery.add_imported(
          article,
          stored[source],
          tile_name(source),
          DateTime.add(base, index, :second)
        )
    end)
  end

  defp tile_name(source) do
    if Bundle.url?(source) do
      source |> URI.parse() |> Map.get(:path) |> to_string() |> Path.basename()
    else
      Path.basename(source)
    end
  end

  defp complain(bundle, message), do: %{bundle | errors: bundle.errors ++ [message]}
  defp warn(bundle, message), do: %{bundle | warnings: bundle.warnings ++ [message]}
end
