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
