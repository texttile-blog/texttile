defmodule Texttile.Import.Bundle do
  @moduledoc """
  One bundle folder, read and judged against IMPORT.md: the typed front
  matter, the body, the gallery in its order, and every complaint the
  dry run will show. Reading never touches the network; the URL checks
  belong to the dry run itself (`Texttile.Import`).
  """

  alias Texttile.Articles
  alias Texttile.Import.Frontmatter

  defstruct name: nil,
            dir: nil,
            title: nil,
            slug: nil,
            date: nil,
            status: "published",
            type: "post",
            tags: [],
            allow_comments: true,
            preview: nil,
            gallery: [],
            body_refs: [],
            body: "",
            errors: [],
            warnings: []

  @keys ~w(title slug date status type tags allow_comments preview gallery)
  @picture_extensions ~w(.png .jpg .jpeg .webp .gif)

  @doc "The supported picture extensions, lowercase, with the dot."
  def picture_extensions, do: @picture_extensions

  @doc "Reads and validates one bundle folder."
  def read(dir) do
    bundle = %__MODULE__{name: Path.basename(dir), dir: dir}

    case File.read(Path.join(dir, "index.md")) do
      {:error, _} ->
        fail(bundle, "index.md is missing")

      {:ok, text} ->
        case Frontmatter.parse(text) do
          {:error, message} -> fail(bundle, "index.md: #{message}")
          {:ok, entries, body} -> build(%{bundle | body: body}, entries)
        end
    end
  end

  @doc """
  Every picture source of the bundle, each once: the gallery in its
  order, then the body references. The preview adds nothing; it must
  match one of these.
  """
  def sources(%__MODULE__{} = bundle) do
    Enum.uniq(bundle.gallery ++ bundle.body_refs)
  end

  @doc "True when the source is a URL, false when it is a bundle path."
  def url?(source), do: String.contains?(source, "://")

  defp fail(bundle, message), do: %{bundle | errors: [message]}

  defp build(bundle, entries) do
    bundle
    |> unknown_keys(entries)
    |> scalar_fields(entries)
    |> list_fields(entries)
    |> derive_slug(entries)
    |> resolve_gallery(entries)
    |> read_body_refs()
    |> check_sources()
    |> check_preview()
    |> unreferenced_files(entries)
  end

  defp complain(bundle, message), do: %{bundle | errors: bundle.errors ++ [message]}
  defp warn(bundle, message), do: %{bundle | warnings: bundle.warnings ++ [message]}

  defp unknown_keys(bundle, entries) do
    entries
    |> Map.keys()
    |> Enum.reject(&(&1 in @keys))
    |> Enum.sort()
    |> Enum.reduce(bundle, &complain(&2, "the key #{&1} is not part of the format"))
  end

  # Each scalar key, checked and put into its typed place.
  defp scalar_fields(bundle, entries) do
    Enum.reduce(
      ~w(title date status type allow_comments preview),
      bundle,
      fn key, bundle ->
        case Map.fetch(entries, key) do
          :error ->
            missing(bundle, key)

          {:ok, value} when is_list(value) ->
            complain(bundle, "#{key} takes one value, not a list")

          {:ok, value} ->
            put_scalar(bundle, key, value)
        end
      end
    )
  end

  defp missing(bundle, "title"), do: complain(bundle, "title is required")
  defp missing(bundle, _key), do: bundle

  defp put_scalar(bundle, "title", ""), do: complain(bundle, "title is required")
  defp put_scalar(bundle, "title", value), do: %{bundle | title: value}

  defp put_scalar(bundle, "date", value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> %{bundle | date: date}
      {:error, _} -> complain(bundle, "date must be YYYY-MM-DD, not #{value}")
    end
  end

  defp put_scalar(bundle, "status", value) when value in ~w(published draft),
    do: %{bundle | status: value}

  defp put_scalar(bundle, "status", value),
    do: complain(bundle, "status is published or draft, not #{value}")

  defp put_scalar(bundle, "type", value) when value in ~w(post page),
    do: %{bundle | type: value}

  defp put_scalar(bundle, "type", value),
    do: complain(bundle, "type is post or page, not #{value}")

  defp put_scalar(bundle, "allow_comments", value) when value in ~w(true false),
    do: %{bundle | allow_comments: value == "true"}

  defp put_scalar(bundle, "allow_comments", value),
    do: complain(bundle, "allow_comments is true or false, not #{value}")

  defp put_scalar(bundle, "preview", value), do: %{bundle | preview: value}

  defp list_fields(bundle, entries) do
    Enum.reduce(~w(tags gallery), bundle, fn key, bundle ->
      case Map.fetch(entries, key) do
        :error -> bundle
        {:ok, value} when not is_list(value) -> complain(bundle, "#{key} takes a list")
        {:ok, value} when key == "tags" -> %{bundle | tags: value}
        {:ok, _value} -> bundle
      end
    end)
  end

  defp derive_slug(bundle, entries) do
    case Map.get(entries, "slug", bundle.title) do
      given when is_binary(given) ->
        case Articles.slugify(given) do
          "" -> complain(bundle, "the slug is empty after normalizing #{inspect(given)}")
          slug -> %{bundle | slug: slug}
        end

      nil ->
        # No slug and no title: the title complaint already stands.
        bundle

      _other ->
        complain(bundle, "slug takes one value, not a list")
    end
  end

  # The gallery key when it is a list; the gallery/ folder otherwise.
  defp resolve_gallery(bundle, entries) do
    case Map.fetch(entries, "gallery") do
      {:ok, list} when is_list(list) ->
        list
        |> Enum.frequencies()
        |> Enum.filter(fn {_source, count} -> count > 1 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()
        |> Enum.reduce(%{bundle | gallery: list}, fn source, bundle ->
          complain(bundle, "the gallery lists #{source} twice")
        end)

      {:ok, _} ->
        bundle

      :error ->
        shorthand =
          bundle.dir
          |> Path.join("gallery")
          |> ls()
          |> Enum.filter(&picture?/1)
          |> Enum.sort()
          |> Enum.map(&"gallery/#{&1}")

        %{bundle | gallery: shorthand}
    end
  end

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      {:error, _} -> []
    end
  end

  defp picture?(name) do
    String.downcase(Path.extname(name)) in @picture_extensions
  end

  defp read_body_refs(bundle) do
    refs =
      bundle.body
      |> Articles.inline_refs()
      |> Enum.flat_map(fn
        %{kind: :done, url: url} -> [url]
        _ -> []
      end)
      |> Enum.uniq()

    %{bundle | body_refs: refs}
  end

  defp check_sources(bundle) do
    bundle |> sources() |> Enum.reduce(bundle, &check_source(&2, &1))
  end

  defp check_source(bundle, source) do
    cond do
      url?(source) ->
        if String.starts_with?(source, ["http://", "https://"]) do
          bundle
        else
          complain(bundle, "the source #{source} is neither http(s) nor a bundle path")
        end

      Path.type(source) != :relative or ".." in Path.split(source) ->
        complain(
          bundle,
          "the source #{source} leaves the bundle folder (no .. and no absolute paths)"
        )

      not picture?(source) ->
        complain(
          bundle,
          "the source #{source} is not a supported picture (PNG, JPEG, WebP, GIF)"
        )

      not File.regular?(Path.join(bundle.dir, source)) ->
        complain(bundle, "the source #{source} is not in the bundle")

      true ->
        bundle
    end
  end

  defp check_preview(%{preview: nil} = bundle), do: bundle

  defp check_preview(bundle) do
    if bundle.preview in sources(bundle) do
      bundle
    else
      complain(bundle, "the preview matches no picture source of the bundle")
    end
  end

  # Everything on disk that the bundle does not speak for. Files an
  # explicit gallery key skips get the sharper warning.
  defp unreferenced_files(bundle, entries) do
    explicit? = is_list(Map.get(entries, "gallery"))
    referenced = MapSet.new(Enum.reject(sources(bundle), &url?/1))

    bundle.dir
    |> files_below()
    |> Enum.reject(&(&1 in ["index.md", "comments.yaml"]))
    |> Enum.reject(&MapSet.member?(referenced, &1))
    |> Enum.sort()
    |> Enum.reduce(bundle, fn file, bundle ->
      cond do
        explicit? and String.starts_with?(file, "gallery/") ->
          warn(bundle, "#{file} is in gallery/, but the gallery key does not list it")

        not explicit? and String.starts_with?(file, "gallery/") and picture?(file) ->
          # the shorthand took it as a tile
          bundle

        true ->
          warn(bundle, "nothing references #{file}")
      end
    end)
  end

  defp files_below(dir) do
    dir
    |> walk("")
    |> Enum.sort()
  end

  defp walk(dir, prefix) do
    dir
    |> ls()
    |> Enum.flat_map(fn name ->
      full = Path.join(dir, name)
      relative = if prefix == "", do: name, else: "#{prefix}/#{name}"

      if File.dir?(full) do
        walk(full, relative)
      else
        [relative]
      end
    end)
  end
end
