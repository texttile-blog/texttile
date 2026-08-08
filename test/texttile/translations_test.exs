defmodule Texttile.TranslationsTest do
  @moduledoc """
  Whether the one file per language is complete.

  A missing translation is not a crash. It is an English sentence in
  the middle of a German page, and nobody sees it until a reader does.
  So the file is read here, and every gap is named.
  """

  use ExUnit.Case, async: true

  alias Texttile.I18n

  @template "priv/gettext/default.pot"

  defp po_path(locale), do: "priv/gettext/#{locale}/LC_MESSAGES/default.po"

  # A message is one of two shapes: one string, or one per plural form.
  defp id(%Expo.Message.Singular{msgid: msgid}), do: IO.iodata_to_binary(msgid)
  defp id(%Expo.Message.Plural{msgid: msgid}), do: IO.iodata_to_binary(msgid)

  defp translated?(%Expo.Message.Singular{msgstr: msgstr}), do: said?(msgstr)

  defp translated?(%Expo.Message.Plural{msgstr: msgstr}),
    do: msgstr |> Map.values() |> Enum.all?(&said?/1)

  defp said?(strings), do: strings |> IO.iodata_to_binary() |> String.trim() != ""

  defp fuzzy?(message), do: "fuzzy" in List.flatten(message.flags)

  defp name_them(ids), do: Enum.map_join(ids, "\n", &("  " <> inspect(&1)))

  @place ~r/%\{(\w+)\}/

  defp places(text), do: @place |> Regex.scan(text) |> MapSet.new(fn [_, name] -> name end)

  # Every translated form beside the English it answers. A plural form
  # answers the singular English for form 0 and the plural for the
  # rest, which is what German has.
  defp said_and_wanted(%Expo.Message.Singular{msgid: msgid, msgstr: msgstr}) do
    [{IO.iodata_to_binary(msgstr), IO.iodata_to_binary(msgid)}]
  end

  defp said_and_wanted(%Expo.Message.Plural{msgid: one, msgid_plural: many, msgstr: msgstr}) do
    for {index, said} <- msgstr do
      wanted = if index == 0, do: one, else: many
      {IO.iodata_to_binary(said), IO.iodata_to_binary(wanted)}
    end
  end

  describe "every language but English" do
    test "has a file, and the file answers every message of the template" do
      wanted = @template |> Expo.PO.parse_file!() |> Map.fetch!(:messages) |> MapSet.new(&id/1)

      for locale <- I18n.locales(), locale != I18n.default_locale() do
        path = po_path(locale)
        assert File.exists?(path), "#{path} is missing"

        have = path |> Expo.PO.parse_file!() |> Map.fetch!(:messages) |> MapSet.new(&id/1)

        assert MapSet.difference(wanted, have) |> MapSet.to_list() == [],
               "#{path} does not know these yet. Run mix gettext.extract --merge."

        assert MapSet.difference(have, wanted) |> MapSet.to_list() == [],
               "#{path} still carries these, and the code no longer says them."
      end
    end

    test "keeps every place the English sentence opens" do
      # A %{name} carries the thing the sentence is about: a link, a
      # password, an address. One dropped in a translation ships a mail
      # with a hole where its link belongs, and Gettext says nothing
      # about a place nobody asked to fill.
      for locale <- I18n.locales(), locale != I18n.default_locale() do
        for message <- locale |> po_path() |> Expo.PO.parse_file!() |> Map.fetch!(:messages),
            {said, wanted} <- said_and_wanted(message) do
          missing = MapSet.difference(places(wanted), places(said))

          assert MapSet.to_list(missing) == [],
                 "#{locale} lost #{inspect(MapSet.to_list(missing))} out of #{inspect(wanted)}"
        end
      end
    end

    test "says every message, and leaves none marked uncertain" do
      for locale <- I18n.locales(), locale != I18n.default_locale() do
        messages = po_path(locale) |> Expo.PO.parse_file!() |> Map.fetch!(:messages)

        empty = messages |> Enum.reject(&translated?/1) |> Enum.map(&id/1)
        assert empty == [], "#{locale} has no words for these:\n" <> name_them(empty)

        fuzzy = messages |> Enum.filter(&fuzzy?/1) |> Enum.map(&id/1)

        assert fuzzy == [],
               "#{locale} guessed at these when the English changed. Read them and drop the " <>
                 "fuzzy flag:\n" <> name_them(fuzzy)
      end
    end
  end
end
