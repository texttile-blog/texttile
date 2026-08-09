defmodule Texttile.I18nTest do
  use Texttile.DataCase, async: false

  alias Texttile.I18n
  alias Texttile.Settings
  alias Texttile.Settings.Setting

  describe "the languages a site can speak" do
    test "English leads, and each language carries the name it calls itself" do
      assert I18n.languages() == [{"en", "English"}, {"de", "Deutsch"}]
      assert I18n.locales() == ["en", "de"]
      assert I18n.default_locale() == "en"
    end

    test "every language but English has a file of its own" do
      known = Gettext.known_locales(TexttileWeb.Gettext)

      for locale <- I18n.locales(), locale != I18n.default_locale() do
        assert locale in known, "#{locale} is offered but priv/gettext/#{locale} is missing"
      end

      # English is the source. Every msgid is the English sentence, so
      # a catalogue for it would hold each sentence twice.
      refute I18n.default_locale() in known
    end
  end

  describe "site_locale/0" do
    test "is the language in the settings" do
      assert I18n.site_locale() == "en"

      {:ok, _} = Settings.put(:language, "de")
      assert I18n.site_locale() == "de"
    end

    test "a language nobody translated falls back to English" do
      # What an install that chose Lithuanian before this version has
      # in its settings table. It must not raise, and it must not show
      # a half-translated site.
      Repo.insert!(%Setting{key: "language", value: "lt"})

      assert I18n.site_locale() == "en"
    end
  end

  describe "put_site_locale/0" do
    test "puts the language of the site on this process" do
      {:ok, _} = Settings.put(:language, "de")

      assert I18n.put_site_locale() == "de"
      assert Gettext.get_locale(TexttileWeb.Gettext) == "de"
    end
  end

  describe "the words in a date" do
    test "English writes the day before the month, and German puts a dot behind it" do
      day = ~D[2026-07-02]

      assert I18n.format_date(day) == "2 July 2026"
      assert I18n.format_day_and_month(day) == "2 July"
      assert I18n.format_short_day(day) == "2 Jul"

      {:ok, _} = Settings.put(:language, "de")
      I18n.put_site_locale()

      assert I18n.format_date(day) == "2. Juli 2026"
      assert I18n.format_day_and_month(day) == "2. Juli"
      assert I18n.format_short_day(day) == "2. Jul"
    end

    test "a date without a day is no date" do
      assert I18n.format_date(nil) == ""
    end

    test "every month has a name, long and short, in both languages" do
      for locale <- I18n.locales() do
        I18n.put_locale(locale)

        for month <- 1..12 do
          assert I18n.month_name(month) != ""
          assert I18n.short_month_name(month) != ""
        end
      end

      I18n.put_locale("de")
      assert I18n.month_name(3) == "März"
      assert I18n.short_month_name(3) == "Mär"
      assert I18n.month_name(12) == "Dezember"
    end

    test "the archive row of the admin area reads the same names" do
      I18n.put_locale("de")

      assert Texttile.Articles.month_name(1) == "Jan"
      assert Texttile.Articles.month_name(3) == "Mär"
    end
  end

  describe "the plain shapes of a moment" do
    @moment ~U[2026-08-09 14:30:45Z]

    test "the admin area reads a moment as numbers, in every language" do
      assert I18n.format_moment(@moment) == "2026-08-09 14:30"
      I18n.put_locale("de")
      assert I18n.format_moment(@moment) == "2026-08-09 14:30"
    end

    test "the day of a moment is as plain" do
      assert I18n.format_plain_day(@moment) == "2026-08-09"
      assert I18n.format_plain_day(~D[2026-08-09]) == "2026-08-09"
    end

    # The gallery's date field writes this shape and Gallery.set_date/3
    # parses it back. The two ends have to agree, so this pins them.
    test "a datetime-local field writes what the gallery reads" do
      written = I18n.format_field_moment(@moment)
      assert written == "2026-08-09T14:30"

      user = Texttile.AccountsFixtures.user_fixture()
      {:ok, article} = Texttile.Articles.create_draft(user)
      image = gallery_image(article)

      {:ok, dated} = Texttile.Gallery.set_date(article.id, image.id, written)
      assert I18n.format_field_moment(dated.gallery_date) == written
    end

    test "no moment at all is no words" do
      assert I18n.format_moment(nil) == ""
      assert I18n.format_plain_day(nil) == ""
      assert I18n.format_field_moment(nil) == ""
    end

    defp gallery_image(article) do
      path = Path.join(System.tmp_dir!(), "i18n-#{System.unique_integer([:positive])}.jpg")
      {:ok, black} = Vix.Vips.Operation.black(20, 10)
      :ok = Vix.Vips.Image.write_to_file(black, path)
      {:ok, image} = Texttile.Gallery.add_file(article, path, "a.jpg")
      image
    end
  end

  describe "the settings only take a language the site speaks" do
    test "English and German go in" do
      assert {:ok, "de"} = Settings.put(:language, "de")
      assert {:ok, "en"} = Settings.put(:language, "en")
    end

    test "a language without translations is refused" do
      assert {:error, _} = Settings.put(:language, "lt")
      assert Settings.get(:language) == "en"
    end
  end
end
