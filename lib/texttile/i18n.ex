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

  use Gettext, backend: TexttileWeb.Gettext

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
  it. Gettext keeps the locale per process, so a plain request and a
  connected LiveView each ask once.

  This reads the settings, so it belongs where a database connection
  belongs to the process. A task that is started and never waited for
  owns none: hand it `site_locale/0` from the process that started it
  and let it call `put_locale/1`.
  """
  def put_site_locale do
    locale = site_locale()
    put_locale(locale)
  end

  @doc """
  Puts a language that was read somewhere else on this process, and
  answers with it. Touches nothing but the process.
  """
  def put_locale(locale) do
    Gettext.put_locale(TexttileWeb.Gettext, locale)
    locale
  end

  ## The words in a date

  # Elixir writes month names in English and takes no other language,
  # so the twelve names are translated here and the dates are built out
  # of them. The feed keeps English on purpose: RFC 822 asks for it.
  @months ~w(January February March April May June July August September October November December)
  @short_months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc "The name of a month, 1 to 12."
  def month_name(number) when number in 1..12 do
    Gettext.gettext(TexttileWeb.Gettext, Enum.at(@months, number - 1))
  end

  @doc "The short name of a month, 1 to 12: what fits in a row of twelve."
  def short_month_name(number) when number in 1..12 do
    Gettext.gettext(TexttileWeb.Gettext, Enum.at(@short_months, number - 1))
  end

  @doc """
  A date the way the reader pages write one: 2 July 2026. German puts
  a dot behind the day, so the shape belongs to the language too.
  """
  def format_date(nil), do: ""

  def format_date(date) do
    gettext("%{day} %{month} %{year}",
      day: date.day,
      month: month_name(date.month),
      year: date.year
    )
  end

  @doc "The same date without the year, for a day inside the current one."
  def format_day_and_month(date) do
    gettext("%{day} %{month}", day: date.day, month: month_name(date.month))
  end

  @doc "A day in a chart: the number and the short month."
  def format_short_day(date) do
    gettext("%{day} %{month}", day: date.day, month: short_month_name(date.month))
  end

  @doc """
  A moment the admin area writes plainly: `2026-08-09 14:30`.

  Not the reader's shape and not the language's. These stand in the
  Log, under a comment and on a gallery tile, where they are read as
  numbers and lined up under each other.
  """
  def format_moment(nil), do: ""
  def format_moment(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  @doc "The day of a moment, as plainly: `2026-08-09`."
  def format_plain_day(nil), do: ""
  def format_plain_day(date), do: Calendar.strftime(date, "%Y-%m-%d")

  @doc """
  A moment the way a `datetime-local` field writes and reads it.

  The gallery's date field sends this shape straight back, and
  `Texttile.Gallery.set_date/3` parses exactly what this writes, so the
  two ends have to be changed together.
  """
  def format_field_moment(nil), do: ""
  def format_field_moment(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M")

  # The twelve names, listed for the extractor: month_name/1 asks for
  # them by a value, so nothing else here is a literal it could read.
  @doc false
  def month_catalogue do
    [
      gettext_noop("January"),
      gettext_noop("February"),
      gettext_noop("March"),
      gettext_noop("April"),
      gettext_noop("May"),
      gettext_noop("June"),
      gettext_noop("July"),
      gettext_noop("August"),
      gettext_noop("September"),
      gettext_noop("October"),
      gettext_noop("November"),
      gettext_noop("December"),
      gettext_noop("Jan"),
      gettext_noop("Feb"),
      gettext_noop("Mar"),
      gettext_noop("Apr"),
      gettext_noop("Jun"),
      gettext_noop("Jul"),
      gettext_noop("Aug"),
      gettext_noop("Sep"),
      gettext_noop("Oct"),
      gettext_noop("Nov"),
      gettext_noop("Dec")
    ]
  end
end
