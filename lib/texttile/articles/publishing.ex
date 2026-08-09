defmodule Texttile.Articles.Publishing do
  @moduledoc """
  What a click on Publish would do, before it does it.

  The rule was spread over nine private functions in the editor, with
  the choice itself made inline in the handler:

      mode = if article.status == "scheduled", do: :as_set, else: :mail

  Three of those functions existed only so the words in the dialog and
  what the click did could not drift apart, and one carried a comment
  saying so. A plan says it once.

  `plan/3` answers what the click means: where the entry lands, on
  which day, whether a mail goes and to how many people. The dialog
  draws the plan instead of working it out again, and `run/3` carries
  out the same plan the person was shown.

  The three choices:

    * `:mail` - publish, and mail the list if the entry asks for it
    * `:quiet` - publish, mail nobody, and record that
    * `:as_set` - publish now, leaving the entry's own mail switch alone

  Publishing never mails by itself. `plan.mails?` is what the click
  asked for, and `plan.recipients` is how many people would really get
  something, which is nobody unless the entry goes live this second,
  carries the mail and has never been mailed before.
  """

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Visibility
  alias Texttile.Newsletter

  defmodule Plan do
    @moduledoc "What a publish would do. See `Texttile.Articles.Publishing`."
    defstruct [
      :choice,
      :status,
      :day,
      :today,
      live_now?: false,
      mails?: false,
      recipients: 0,
      force?: false
    ]
  end

  @doc """
  What a click on Publish means for this entry. A scheduled entry is
  already dated and already decided, so the click only means "now" and
  leaves the mail switch as it stands.
  """
  def choice(%Article{status: "scheduled"}), do: :as_set
  def choice(%Article{}), do: :mail

  @doc """
  Where this entry would land and who would hear about it. `today:`
  names the day it is judged against.
  """
  def plan(%Article{} = article, choice, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    force? = article.status == "scheduled"
    {day, status} = landing(article, force: force?, today: today)
    live_now? = status == Visibility.live_status()
    mails? = mails?(article, choice)

    %Plan{
      choice: choice,
      status: status,
      day: day,
      today: today,
      live_now?: live_now?,
      force?: force?,
      mails?: mails?,
      recipients: recipients(article, mails?, live_now?)
    }
  end

  @doc """
  Where a publish lands: the day it takes and the status it gets. The
  one reading of the date, so `Texttile.Articles.publish/3` and the
  words before the click cannot drift apart.
  """
  def landing(%Article{} = article, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    day = if opts[:force], do: today, else: article.publish_date || today
    future? = Date.compare(day, today) == :gt

    {day, if(future?, do: "scheduled", else: Visibility.live_status())}
  end

  @doc """
  Carries the plan out: the entry records what the click asked for
  about the mail, then goes live or is scheduled.

  The verb carries the decision, so the record follows it. What the
  entry remembers is what the click asked for, and the go-live clock
  reads the same field when a scheduled entry goes live on its own.
  """
  def run(%Article{} = article, user, %Plan{} = plan) do
    article
    |> remember_mail(plan)
    |> Articles.publish(user, force: plan.force?, today: plan.today)
  end

  defp remember_mail(%Article{notify_on_publish: wanted} = article, %Plan{mails?: wanted}) do
    article
  end

  defp remember_mail(article, %Plan{mails?: wanted}) do
    {:ok, moved} = Articles.update_settings(article, %{"notify_on_publish" => wanted})
    moved
  end

  # A page never mails anybody, so a click records that instead of
  # leaving a flag armed for the day somebody turns the page into a post.
  defp mails?(%Article{type: type}, _choice) when type != "post", do: false
  defp mails?(_article, :mail), do: true
  defp mails?(_article, :quiet), do: false
  defp mails?(article, :as_set), do: article.notify_on_publish

  # Nobody, unless the entry both goes live this second and carries the
  # mail: a click that only moves a future date is a scheduling, and a
  # mail that has already gone never goes twice.
  defp recipients(%Article{notified_on: nil}, true, true), do: length(Newsletter.confirmed())
  defp recipients(_article, _mails?, _live_now?), do: 0
end
