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

  @languages ~w(en de lt)

  # key => {type, default}. A :file value is a path below the uploads
  # root, written by Texttile.Uploads, never by a form field.
  @keys %{
    site_title: {:string, "Texttile"},
    site_description: {:string, "Text plus tiles. One text at a time."},
    language: {:string, "en"},
    about_markdown: {:string, ""},
    front_page: {:string, "latest"},
    theme_css: {:string, ""},
    comments_require_confirmation: {:boolean, true},
    image_max_edge: {:integer, 2560},
    logo: {:file, nil},
    logo_name: {:file, nil},
    favicon: {:file, nil},
    favicon_name: {:file, nil}
  }

  @doc "The value of one setting, typed, falling back to its default."
  def get(key) when is_map_key(@keys, key) do
    case Repo.get(Setting, to_string(key)) do
      nil -> default(key)
      %Setting{value: value} -> load(key, value)
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

  defp validate(:language, value) do
    if value in @languages, do: :ok, else: {:error, "unknown language"}
  end

  defp validate(:front_page, "latest"), do: :ok
  defp validate(:front_page, _), do: {:error, "unknown front page"}

  defp validate(:image_max_edge, n) when n < 800, do: {:error, "at least 800 px"}
  defp validate(:image_max_edge, n) when n > 10_000, do: {:error, "at most 10000 px"}

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
