defmodule TexttileWeb.JsStrings do
  @moduledoc """
  The words the editor's hooks say.

  The gallery, the lightbox and the saved mark write their own text in
  the browser, so no template can carry it. The admin layout renders
  this object into the page instead, and `assets/js/i18n.js` reads it.

  The English sentence is the key, the way a msgid is, so the hooks
  keep their English text and this is only what to say instead. That
  makes the object empty on an English site, and it makes an
  untranslated sentence read as English.

  The list is the contract with the hooks. A sentence a hook says and
  this list does not name stays English on every site, and the
  translation test cannot see it: when you add text to a hook, add it
  here.
  """

  use Gettext, backend: TexttileWeb.Gettext

  alias Texttile.I18n

  # Every sentence the admin bundle says, in the English it says it in.
  # gettext_noop only marks them for the extractor; the translating
  # happens in json/0, because the hooks ask by the English sentence.
  @sources [
    # gallery.js and gallery_core.js: the upload queue
    gettext_noop("queued"),
    gettext_noop("uploading %{pct}%"),
    gettext_noop("processing"),
    gettext_noop("upload failed"),
    gettext_noop("bigger than the %{roof} MB roof"),
    gettext_noop("%{name} is bigger than the %{roof} MB roof."),
    gettext_noop("%{name} failed to upload. Retry or remove it."),
    gettext_noop("%{count} on the way"),
    gettext_noop("Retry"),
    gettext_noop("Remove"),
    gettext_noop("Cancel"),
    # the gallery lightbox
    gettext_noop("Full size"),
    gettext_noop("Close"),
    gettext_noop("Previous"),
    gettext_noop("Next"),
    gettext_noop("Previous tile"),
    gettext_noop("Next tile"),
    gettext_noop("Open original"),
    gettext_noop("Original"),
    gettext_noop("Delete tile"),
    gettext_noop("Delete"),
    gettext_noop("Date"),
    gettext_noop("The date saves itself and sorts the gallery."),
    gettext_noop("That date could not be read"),
    gettext_noop("Saved · just now"),
    gettext_noop("Loading the full size…"),
    gettext_noop("%{date} · %{index} of %{count}"),
    gettext_noop("%{name} deleted"),
    gettext_noop("Undo"),
    # media_lightbox.js: a film the reader opens from the body
    gettext_noop("This film is still being converted. It plays here once that is done."),
    # body_ed_core.js: the body editor
    gettext_noop("Done. Untick it."),
    gettext_noop("Open. Tick it off."),
    gettext_noop("Body, Markdown"),
    gettext_noop("the pasted picture"),
    # copy_out.js: the button that hands a value over
    gettext_noop("Copy"),
    gettext_noop("Copied"),
    # app.js: the saved mark in the topbar
    gettext_noop("Saved"),
    gettext_noop("saved"),
    gettext_noop("saved %{time}"),
    gettext_noop("Last saved · just now"),
    gettext_noop("Last saved %{time}"),
    gettext_noop("The last save was at %{time}.")
  ]

  @doc """
  What the hooks should say instead, as JSON. An empty object while the
  site speaks the language of the source: then the hooks are already
  right.
  """
  def json do
    if I18n.site_locale() == I18n.default_locale() do
      "{}"
    else
      @sources
      |> Map.new(&{&1, translate(&1)})
      |> Jason.encode!(escape: :html_safe)
    end
  end

  # The places stay open: the hook fills them, not the server. So every
  # %{name} is bound to itself and travels through the interpolation
  # unchanged. Without that, Gettext would call the binding missing and
  # hand back a sentence with a hole in it.
  @placeholder ~r/%\{(\w+)\}/

  defp translate(source) do
    bindings =
      @placeholder
      |> Regex.scan(source)
      |> Map.new(fn [whole, name] -> {String.to_atom(name), whole} end)

    Gettext.gettext(TexttileWeb.Gettext, source, bindings)
  end
end
