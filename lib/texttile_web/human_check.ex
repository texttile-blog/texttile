defmodule TexttileWeb.HumanCheck do
  @moduledoc """
  Did a person fill in this public form?

  The two forms a stranger can send - the comment form and the
  newsletter band - wear the same two invisible filters, and this
  module is both halves of them: it mints the stamp a form is drawn
  with, and it judges the answer. A filled honeypot, a form sent back
  within a script's seconds, a stamp that was never drawn or was drawn
  for another entry, and a stamp older than a week all read as not a
  person. The filters are always on and have no configuration.

  A dropped request is the caller's business; the rule here is only the
  judgment. The rate limiter is asked separately, because it is spent
  on storable requests only and this check runs before validation.

  `now:` names the moment the judgment is made at, the way the domain
  modules take it, so a test can stand on either side of the trap
  without sleeping.
  """

  alias Texttile.Articles.Article

  # Less than this many seconds between drawing the form and sending it
  # back is a script, not a person typing.
  @min_age 3

  # A stamp lives a week: a tab left open over a weekend still posts,
  # a harvested stamp does not live forever.
  @max_age 7 * 86_400

  @doc """
  The stamp a form carries: a signed note of which form was drawn, for
  what, and when. `{:comment, article_id}` or `:newsletter`.
  """
  def stamp(form, opts \\ [])

  def stamp({:comment, article_id}, opts) do
    Phoenix.Token.sign(TexttileWeb.Endpoint, "comment form", {article_id, moment(opts)})
  end

  def stamp(:newsletter, opts) do
    Phoenix.Token.sign(TexttileWeb.Endpoint, "newsletter form", moment(opts))
  end

  @doc """
  Whether a person filled in the form these params came back from:
  the honeypot (`url`) is empty, and the stamp (`t`) is this form's
  own, old enough for a person's typing and not yet expired.
  """
  def human?(form, params, opts \\ []) do
    honeypot_empty?(params) and timing?(form, text(params["t"]), moment(opts))
  end

  defp honeypot_empty?(params), do: text(params["url"]) == ""

  defp timing?({:comment, %Article{id: article_id}}, token, now) do
    case verify("comment form", token) do
      {:ok, {^article_id, signed_at}} -> aged?(signed_at, now)
      _other -> false
    end
  end

  defp timing?(:newsletter, token, now) do
    case verify("newsletter form", token) do
      {:ok, signed_at} when is_integer(signed_at) -> aged?(signed_at, now)
      _other -> false
    end
  end

  # The moment in the stamp answers both traps, so the whole judgment
  # follows `now:`; the signature only has to be real.
  defp verify(salt, token) do
    Phoenix.Token.verify(TexttileWeb.Endpoint, salt, token, max_age: :infinity)
  end

  defp aged?(signed_at, now) when is_integer(signed_at) do
    age = now - signed_at
    age >= @min_age and age <= @max_age
  end

  defp aged?(_signed_at, _now), do: false

  defp moment(opts), do: Keyword.get(opts, :now) || System.system_time(:second)

  # A form field is one line of text. A caller who sends a list or a
  # map instead gets it read as nothing, not a crash.
  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""
end
