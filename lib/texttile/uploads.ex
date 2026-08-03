defmodule Texttile.Uploads do
  @moduledoc """
  The uploaded files on disk. Everything lives below one root from the
  install config (`UPLOADS_PATH`), so one volume carries it all: the
  same layout on a laptop, in a container and on Fly.

      site/    the logo and the favicon
      images/  the originals of every picture (comes with the editor)
      cache/   renditions, disposable (see Texttile.Images)
  """

  alias Texttile.Settings

  @doc "The uploads root from the install config."
  def root do
    Application.fetch_env!(:texttile, :uploads_path)
  end

  @doc "The absolute path behind a stored relative one."
  def absolute(relative), do: Path.join(root(), relative)

  @marks [:logo, :favicon]
  @mark_extensions ~w(.svg .png)

  @doc """
  Stores an uploaded logo or favicon and remembers it in the settings.
  The stored name carries a random tag, so a browser never clings to a
  stale one; the earlier file goes with the swap.
  """
  def put_site_mark(mark, source_path, original_name) when mark in @marks do
    extension = original_name |> Path.extname() |> String.downcase()

    if extension in @mark_extensions do
      tag = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      relative = "site/#{mark}-#{tag}#{extension}"
      destination = absolute(relative)

      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source_path, destination)

      remove_stored_file(mark)
      {:ok, _} = Settings.put(mark, relative)
      {:ok, _} = Settings.put(:"#{mark}_name", original_name)
      {:ok, relative}
    else
      {:error, "SVG or PNG, please"}
    end
  end

  @doc "Back to the default mark: the file goes, the settings clear."
  def reset_site_mark(mark) when mark in @marks do
    remove_stored_file(mark)
    {:ok, _} = Settings.put(mark, nil)
    {:ok, _} = Settings.put(:"#{mark}_name", nil)
    :ok
  end

  defp remove_stored_file(mark) do
    case Settings.get(mark) do
      nil -> :ok
      relative -> File.rm(absolute(relative))
    end
  end
end
