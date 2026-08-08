defmodule Texttile.Settings do
  @moduledoc """
  The site settings: everything that may change while you live with the
  site. Everything else is config at install time (`Texttile.Config`).

  Each setting is one row, stored as text. This module owns the list of
  keys, their types, their defaults and their rules; an absent row means
  the default. Every accepted change is announced on the settings topic.
  """

  import Ecto.Query

  alias Texttile.Repo
  alias Texttile.Settings.Setting

  @topic "settings"

  # key => {type, default}. A :file value is a path below the uploads
  # root, written by Texttile.Uploads, never by a form field.
  @keys %{
    site_title: {:string, "Texttile"},
    site_description: {:string, "Text plus tiles. One text at a time."},
    language: {:string, "en"},
    about_markdown: {:string, ""},
    front_page: {:string, "latest"},
    theme_css: {:string, ""},
    site_visibility: {:string, "public"},
    site_password: {:string, ""},
    comments_require_confirmation: {:boolean, true},
    notify_on_comment: {:boolean, true},
    posts_per_page: {:integer, 10},
    image_max_edge: {:integer, 2560},
    video_max_edge: {:integer, 1280},
    logo: {:file, nil},
    logo_name: {:file, nil},
    favicon: {:file, nil},
    favicon_name: {:file, nil}
  }

  # The iris theme is the default the whole site wears, admin and public
  # side alike, while no theme.css is stored. Embedded at compile time;
  # the file in assets/ stays the single source.
  @iris_theme_path Path.expand("../../assets/css/theme.css", __DIR__)
  @external_resource @iris_theme_path
  @iris_theme File.read!(@iris_theme_path)

  @doc "The iris theme: what `theme_css` means while it is empty."
  def default_theme_css, do: @iris_theme

  @doc "The theme the site wears right now: the stored one, or iris."
  def theme_css do
    case get(:theme_css) do
      "" -> default_theme_css()
      custom -> custom
    end
  end

  @doc """
  The colour a browser paints its own chrome with, for the theme-color
  meta tag. That chrome sits against the bar at the top of the page, so
  it takes the bar's colour, not the page's. The bar is translucent by
  design, so it is laid over the page colour first. A theme that
  answers neither token falls back to the iris page.
  """
  # Every page render asks for this, so the two patterns are compiled
  # once instead of per call.
  @page_token ~r/--tt-page\s*:\s*([^;}]+)/
  @bar_token ~r/--tt-bar\s*:\s*([^;}]+)/

  def theme_color do
    css = theme_css()
    page = color(css, @page_token) || {250, 249, 247, 1.0}

    css
    |> color(@bar_token)
    |> Kernel.||(page)
    |> over(page)
  end

  # The last declaration wins, the way the browser reads it.
  defp color(css, token) do
    token
    |> Regex.scan(css)
    |> List.last()
    |> case do
      [_whole, value] -> value |> String.trim() |> parse_color()
      _ -> nil
    end
  end

  defp parse_color("#" <> hex) do
    case hex do
      <<r::binary-1, g::binary-1, b::binary-1>> -> rgba(r <> r, g <> g, b <> b, "ff")
      <<r::binary-2, g::binary-2, b::binary-2>> -> rgba(r, g, b, "ff")
      <<r::binary-2, g::binary-2, b::binary-2, a::binary-2>> -> rgba(r, g, b, a)
      _ -> nil
    end
  end

  defp parse_color("rgb" <> rest) do
    numbers =
      rest
      |> String.trim_leading("a")
      |> String.trim()
      |> String.trim_leading("(")
      |> String.trim_trailing(")")
      |> String.split([",", "/", " "], trim: true)
      |> Enum.map(&number/1)

    case numbers do
      [r, g, b] when is_float(r) and is_float(g) and is_float(b) ->
        {round(r), round(g), round(b), 1.0}

      [r, g, b, a] when is_float(r) and is_float(g) and is_float(b) and is_float(a) ->
        {round(r), round(g), round(b), a}

      _ ->
        nil
    end
  end

  defp parse_color(_other), do: nil

  # CSS writes .93 where Elixir wants 0.93, and an alpha may be a
  # percentage instead of a fraction.
  defp number(text) do
    text = String.trim(text)

    {text, scale} =
      if String.ends_with?(text, "%"), do: {String.trim_trailing(text, "%"), 100}, else: {text, 1}

    text = if String.starts_with?(text, "."), do: "0" <> text, else: text

    case Float.parse(text) do
      {value, ""} -> value / scale
      _ -> nil
    end
  end

  defp rgba(r, g, b, a) do
    with {r, ""} <- Integer.parse(r, 16),
         {g, ""} <- Integer.parse(g, 16),
         {b, ""} <- Integer.parse(b, 16),
         {a, ""} <- Integer.parse(a, 16) do
      {r, g, b, a / 255}
    else
      _ -> nil
    end
  end

  defp over({r, g, b, a}, {pr, pg, pb, _}) do
    a = a |> max(0.0) |> min(1.0)
    mix = fn top, under -> round(top * a + under * (1 - a)) end

    "#" <>
      ([mix.(r, pr), mix.(g, pg), mix.(b, pb)]
       |> Enum.map_join(&(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
       |> String.downcase())
  end

  @doc "The value of one setting, typed, falling back to its default."
  def get(key) when is_map_key(@keys, key) do
    case Repo.get(Setting, to_string(key)) do
      nil -> default(key)
      %Setting{value: value} -> load(key, value)
    end
  end

  @doc """
  Whether a password stands in front of the blog: it is protected, and
  the word is not blank. A blank word guards nothing, whatever the
  switch says, and everything that answers to the password - the gate,
  the mail that carries the word, the feed that then does not exist -
  reads the rule here.
  """
  def guarded? do
    get(:site_visibility) == "protected" and get(:site_password) != ""
  end

  @doc """
  The name the site goes by: its title, or Texttile while the title is
  blank. It names the browser tab, the wordmark and the sender of mail.
  """
  def site_title do
    case String.trim(get(:site_title)) do
      "" -> default(:site_title)
      title -> title
    end
  end

  @doc "Every setting as one map, typed."
  def all do
    stored = Map.new(Repo.all(Setting), &{&1.key, &1.value})

    Map.new(@keys, fn {key, _} ->
      case Map.fetch(stored, to_string(key)) do
        {:ok, value} -> {key, load(key, value)}
        :error -> {key, default(key)}
      end
    end)
  end

  @doc """
  Stores one setting. The raw value comes straight from a form: strings
  are cast to the key's type and checked against its rules. `nil` clears
  the row, so the default answers again. Returns the typed value that is
  now in force.
  """
  def put(key, raw) do
    with {:ok, _} <- known(key),
         {:ok, value} <- cast(key, raw),
         :ok <- validate(key, value) do
      store(key, value)

      # A new limit means every cached rendition is the wrong size now.
      if key == :image_max_edge, do: Texttile.Images.clear_cache()

      broadcast(key, value)
      {:ok, value}
    end
  end

  @doc "Subscribes the caller to `{:setting_changed, key, value}` messages."
  def subscribe do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)
  end

  defp known(key) when is_map_key(@keys, key), do: {:ok, key}
  defp known(key), do: {:error, "unknown setting #{inspect(key)}"}

  defp default(key), do: @keys |> Map.fetch!(key) |> elem(1)

  defp type(key), do: @keys |> Map.fetch!(key) |> elem(0)

  ## Casting: what a form sends becomes the key's type

  defp cast(_key, nil), do: {:ok, nil}

  defp cast(key, raw) do
    case {type(key), raw} do
      {:string, value} when is_binary(value) -> {:ok, value}
      {:file, value} when is_binary(value) -> {:ok, value}
      {:boolean, value} when is_boolean(value) -> {:ok, value}
      {:boolean, "true"} -> {:ok, true}
      {:boolean, "false"} -> {:ok, false}
      {:integer, value} when is_integer(value) -> {:ok, value}
      {:integer, value} when is_binary(value) -> cast_integer(value)
      _ -> {:error, "cannot use #{inspect(raw)} here"}
    end
  end

  defp cast_integer(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "a number"}
    end
  end

  ## Rules per key

  defp validate(_key, nil), do: :ok

  # Texttile.I18n owns the list: a language exists when its translation
  # file does. Asked at runtime, so the two modules stay free of each
  # other at compile time.
  defp validate(:language, value) do
    if Texttile.I18n.known?(value), do: :ok, else: {:error, "unknown language"}
  end

  # The front page is the latest-texts list, or one fixed page as
  # "page:<id>". A page that later disappears falls back to the list.
  defp validate(:front_page, "latest"), do: :ok

  defp validate(:front_page, "page:" <> id) do
    if id =~ ~r/\A\d+\z/, do: :ok, else: {:error, "unknown front page"}
  end

  defp validate(:front_page, _), do: {:error, "unknown front page"}

  defp validate(:site_visibility, value) when value in ~w(public protected), do: :ok
  defp validate(:site_visibility, _), do: {:error, "public or protected"}

  defp validate(:posts_per_page, n) when n < 1, do: {:error, "at least 1 text"}
  defp validate(:posts_per_page, n) when n > 200, do: {:error, "at most 200 texts"}

  defp validate(:image_max_edge, n) when n < 800, do: {:error, "at least 800 px"}
  defp validate(:image_max_edge, n) when n > 10_000, do: {:error, "at most 10000 px"}

  # A converted video is never made again, so the roof stays where a
  # phone and a laptop both play the file without stuttering.
  defp validate(:video_max_edge, n) when n < 480, do: {:error, "at least 480 px"}
  defp validate(:video_max_edge, n) when n > 3840, do: {:error, "at most 3840 px"}

  defp validate(_key, _value), do: :ok

  defp store(key, nil) do
    Repo.delete_all(from s in Setting, where: s.key == ^to_string(key))
  end

  defp store(key, value) do
    Repo.insert!(%Setting{key: to_string(key), value: dump(value)},
      on_conflict: {:replace, [:value]},
      conflict_target: :key
    )
  end

  defp dump(value) when is_binary(value), do: value
  defp dump(value), do: to_string(value)

  defp load(key, value) do
    case type(key) do
      :integer -> String.to_integer(value)
      :boolean -> value == "true"
      _ -> value
    end
  end

  defp broadcast(key, value) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:setting_changed, key, value})
  end
end
