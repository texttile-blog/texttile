defmodule TexttileWeb.UploadNews do
  @moduledoc """
  What the editor's one upload message means.

  The files and the running requests live in the holder's browser
  (assets/js/uploads.js); the hook crosses the seam once per change
  with `upload_state {files, news}`. `files` is the standing state and
  becomes the progress display; each item of `news` is something that
  just happened and may owe the entry's Log a line, the state line a
  note, or both.

  A file name is client text: it gets a short leash before it reaches
  the Log. Malformed news reads as nothing, not as a crash.
  """

  use Gettext, backend: TexttileWeb.Gettext

  @doc "The progress display: file name to percent, leashed."
  def pcts(files) when is_list(files) do
    for %{"name" => name, "pct" => pct} <- files,
        is_binary(name) and is_number(pct),
        into: %{},
        do: {clean_file(name), pct}
  end

  def pcts(_other), do: %{}

  @doc """
  One piece of news as what it owes: `%{log:, note:, needs_lock:}`, or
  nil for a shape this module does not speak. Everything that writes
  into the entry or its Log needs the lock; the two answers about the
  browser's own state (`too_big`, `retry_missing`) do not.
  """
  def read(%{"kind" => "inserted", "names" => names}) when is_list(names) do
    log =
      case names do
        [one] -> "put #{clean_file(one)} into the text"
        many -> "put #{length(many)} images into the text"
      end

    %{log: log, note: nil, needs_lock: true}
  end

  def read(%{"kind" => "done", "name" => name}) do
    %{log: "#{clean_file(name)} is in the text", note: nil, needs_lock: true}
  end

  def read(%{"kind" => "failed", "name" => name, "pct" => pct}) when is_number(pct) do
    file = clean_file(name)

    %{
      log: "#{file} failed to upload into the text",
      note: "#{file} failed at #{round(pct)}% · retry or remove it under the text",
      needs_lock: true
    }
  end

  def read(%{"kind" => "refused", "name" => name, "of" => of}) do
    {file, of} = {clean_file(name), clean_file(of)}

    %{
      log: "#{file} is already in this entry, as #{of}",
      note: gettext("This picture is already in this entry, as %{name}.", name: of),
      needs_lock: true
    }
  end

  def read(%{"kind" => "retried", "name" => name}) do
    %{log: "retried the upload of #{clean_file(name)}", note: nil, needs_lock: true}
  end

  def read(%{"kind" => "removed", "name" => name, "how" => how}) do
    file = clean_file(name)

    log =
      if how == "cancel",
        do: "cancelled the upload of #{file}",
        else: "took the marker for #{file} out of the text"

    %{log: log, note: nil, needs_lock: true}
  end

  def read(%{"kind" => "too_big", "names" => names, "roof" => roof})
      when is_list(names) and is_number(roof) do
    joined = names |> Enum.map(&clean_file/1) |> Enum.join(", ")

    note =
      ngettext(
        "%{names} is over the %{roof} MB roof and was not uploaded",
        "%{names} are over the %{roof} MB roof and were not uploaded",
        length(names),
        names: joined,
        roof: roof
      )

    %{log: nil, note: note, needs_lock: false}
  end

  def read(%{"kind" => "retry_missing", "name" => name}) do
    note =
      gettext(
        "The file for %{file} is not in this browser any more · remove the marker and paste the image again",
        file: clean_file(name)
      )

    %{log: nil, note: note, needs_lock: false}
  end

  def read(_other), do: nil

  defp clean_file(file), do: file |> to_string() |> String.slice(0, 120)
end
