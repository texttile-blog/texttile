defmodule Texttile.I18n do
  @moduledoc """
  The one language the site speaks.

  A blog has a language, a reader does not: the entries are written in
  one language, so the words around them are written in it too. The
  `language` setting names it, this module hands it to every process
  that writes words, and one file per language holds all of them
  (`priv/gettext/<locale>/LC_MESSAGES/default.po`).

  English is the language of the source. Every msgid is the English
  sentence itself, so a missing translation reads as English instead of
  as a key.
  """

  alias Texttile.Settings

  # This list is the whole language model: one entry per translation
  # file, under the name the language calls itself. English stands
  # first because it is what the code says. To add a language, add a
  # line here and run `mix gettext.merge priv/gettext --locale <code>`.
  @languages [{"en", "English"}, {"de", "Deutsch"}]
  @locales Enum.map(@languages, &elem(&1, 0))
  @default_locale "en"

  @doc "Every language the site offers, as `{code, the name it calls itself}`."
  def languages, do: @languages

  @doc "Only the codes, English first."
  def locales, do: @locales

  @doc "The language of the source, and the answer to anything unknown."
  def default_locale, do: @default_locale

  @doc "Whether the site can speak this language."
  def known?(locale), do: locale in @locales

  @doc """
  The language of the site. A stored language this version no longer
  translates reads as English: a page half in one language and half in
  another is worse than an English one.
  """
  def site_locale do
    locale = Settings.get(:language)
    if known?(locale), do: locale, else: @default_locale
  end

  @doc """
  Puts the site language on the process that calls it, and answers with
  it. Gettext keeps the locale per process, so everything that writes
  words outside a plain request - a connected LiveView, a mail task,
  the scheduler - has to ask for it once.
  """
  def put_site_locale do
    locale = site_locale()
    Gettext.put_locale(TexttileWeb.Gettext, locale)
    locale
  end
end
