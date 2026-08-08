defmodule TexttileWeb.EctoMessages do
  @moduledoc """
  The messages Ecto writes, listed so that the extractor finds them.

  Everything a person reads lives in one file per language. Ecto's own
  messages are the one thing the tool cannot see: a changeset carries
  them out of the library, not out of this code, so
  `mix gettext.extract` never meets them.

  This list is that meeting. `gettext_noop` marks a string for the
  extractor without translating anything, so nothing here runs at
  render time; `TexttileWeb.CoreComponents.translate_error/1` does the
  translating, and finds these entries in the same file as the rest.

  The list follows Ecto. A validation whose message is not here shows
  in English on a German site, and the translation test says so.
  """

  use Gettext, backend: TexttileWeb.Gettext

  @doc "Every Ecto message, in the form the extractor reads."
  def catalogue do
    [
      # Ecto.Changeset.cast/4
      gettext_noop("can't be blank"),
      # Ecto.Changeset.unique_constraint/3
      gettext_noop("has already been taken"),
      # Ecto.Changeset.put_change/3
      gettext_noop("is invalid"),
      # Ecto.Changeset.validate_acceptance/3
      gettext_noop("must be accepted"),
      # Ecto.Changeset.validate_format/3
      gettext_noop("has invalid format"),
      # Ecto.Changeset.validate_subset/3
      gettext_noop("has an invalid entry"),
      # Ecto.Changeset.validate_exclusion/3
      gettext_noop("is reserved"),
      # Ecto.Changeset.validate_confirmation/3
      gettext_noop("does not match confirmation"),
      # Ecto.Changeset.no_assoc_constraint/3
      gettext_noop("is still associated with this entry"),
      gettext_noop("are still associated with this entry"),
      # Ecto.Changeset.validate_length/3
      ngettext_noop("should have %{count} item(s)", "should have %{count} item(s)"),
      ngettext_noop("should be %{count} character(s)", "should be %{count} character(s)"),
      ngettext_noop("should be %{count} byte(s)", "should be %{count} byte(s)"),
      ngettext_noop(
        "should have at least %{count} item(s)",
        "should have at least %{count} item(s)"
      ),
      ngettext_noop(
        "should be at least %{count} character(s)",
        "should be at least %{count} character(s)"
      ),
      ngettext_noop("should be at least %{count} byte(s)", "should be at least %{count} byte(s)"),
      ngettext_noop(
        "should have at most %{count} item(s)",
        "should have at most %{count} item(s)"
      ),
      ngettext_noop(
        "should be at most %{count} character(s)",
        "should be at most %{count} character(s)"
      ),
      ngettext_noop("should be at most %{count} byte(s)", "should be at most %{count} byte(s)"),
      # Ecto.Changeset.validate_number/3
      gettext_noop("must be less than %{number}"),
      gettext_noop("must be greater than %{number}"),
      gettext_noop("must be less than or equal to %{number}"),
      gettext_noop("must be greater than or equal to %{number}"),
      gettext_noop("must be equal to %{number}")
    ]
  end
end
