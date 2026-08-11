defmodule Texttile.Articles.Listing do
  @moduledoc """
  The list of entries a screen shows: the archive of years and months
  over it, the period it is narrowed to, and the pager over what is
  left.

  The reader's list at /blog and the admin's Entries grid are the same
  list cut the same way; this module is the one place that cuts it.
  The caller brings the entries the search or the filter found and the
  year, the month and the page that were asked for, as the address or
  the screen wrote them; the answer is what the page actually shows.
  """

  alias Texttile.Settings

  defstruct entries: [],
            year: nil,
            month: nil,
            years: [],
            months: [],
            page: 1,
            pages: 1,
            shown: 0,
            across_years: 0

  @doc """
  The page of a list that answers what was asked for.

  `wanted` may carry `:year`, `:month` and `:page`, each as a number or
  as the string an address writes; nonsense reads as nothing asked. A
  year the list cannot show lets go rather than leaving an empty grid
  behind, and a page outside the row lands on the last page: a bookmark
  from a longer blog is no error.

  One page size for the whole installation, so the grid an admin works
  in is cut the same way as the list a reader walks.
  """
  def assemble(found, wanted \\ []) do
    {year, month} = settle_period(found, number(wanted[:year]), number(wanted[:month]))
    {years, months} = periods(found, year)
    in_period = Enum.filter(found, &in_period?(&1, year, month))

    per_page = Settings.get(:posts_per_page)
    pages = max(div(length(in_period) - 1, per_page) + 1, 1)
    page = min(number(wanted[:page]) || 1, pages)

    %__MODULE__{
      entries: Enum.slice(in_period, (page - 1) * per_page, per_page),
      year: year,
      month: month,
      years: years,
      months: months,
      page: page,
      pages: pages,
      # the count over the grid speaks of everything in the period, not
      # of the page it happens to show
      shown: length(in_period),
      # what the search found across every year: the number "All years"
      # carries, so it counts the same way the years beside it do
      across_years: length(found)
    }
  end

  @doc """
  Whether an entry falls in a period. `nil` for the year means every
  year, `nil` for the month means the whole year. An entry without a
  publish date falls in no year at all: it is not in the archive until
  it has a day.
  """
  def in_period?(_article, nil, _month), do: true
  def in_period?(%{publish_date: nil}, _year, _month), do: false
  def in_period?(%{publish_date: date}, year, nil), do: date.year == year

  def in_period?(%{publish_date: date}, year, month),
    do: date.year == year and date.month == month

  @doc """
  The archive over a list of entries: `{years, months}`.

  `years` is every year the list touches, newest first, each with how
  many entries it holds. `months` is empty until a year is open, and
  then it holds only the months of that year that carry something: a
  month nobody wrote in is not a choice, and a row of twelve where half
  of them do nothing reads as a calendar.

  The counts come from the list as it stands, so they follow whatever
  the search has narrowed it to and a year that holds nothing for the
  term goes quiet instead of lying about it.
  """
  def periods(articles, year) do
    years =
      articles
      |> Enum.flat_map(fn
        %{publish_date: nil} -> []
        %{publish_date: date} -> [date.year]
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {y, _count} -> -y end)

    months =
      if year do
        for month <- 1..12,
            count = Enum.count(articles, &in_period?(&1, year, month)),
            count > 0,
            do: {month, count}
      else
        []
      end

    {years, months}
  end

  @doc """
  The year and the month a list can actually show, out of what was
  asked for. A search can empty the year that is open; then the year
  lets go, rather than showing a page with nothing on it. A month only
  ever belongs to the year over it.
  """
  def settle_period(articles, year, month) do
    year = if year && Enum.any?(articles, &in_period?(&1, year, nil)), do: year
    month = if year && month && Enum.any?(articles, &in_period?(&1, year, month)), do: month
    {year, month}
  end

  # A page number, a year or a month as the address writes them, or nil.
  defp number(number) when is_integer(number) and number > 0, do: number

  defp number(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp number(_), do: nil
end
