defmodule TexttileWeb.StatsLive do
  @moduledoc """
  The Stats overview: how many people read the blog, and what they
  read.

  Three figures for the last thirty days, a bar for every day of them,
  the most read entries of all time, where the readers came from, and
  the addresses that are no entry: the front door, the list, the tag
  archives. The design comes from the round-14 prototype.

  The screen shows what it loaded. Numbers that move while somebody
  watches them are a distraction, not a report.
  """

  use TexttileWeb, :live_view

  import TexttileWeb.StatsComponents

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Stats

  @window 30

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Stats")
     |> assign(:window, @window)
     |> assign(:summary, Stats.summary(@window))
     |> assign(:days, Stats.by_day(@window))
     |> assign(:top, Stats.top_articles(20))
     |> assign(:referrers, Stats.referrers(@window))
     |> assign(:pages, Stats.other_pages(@window))
     |> assign(:comment_counts, Comments.count_map())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Stats"
      active="stats"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[1060px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">Stats</h1>
        <p class="lead" id="statsSub">
          Counted by this server alone. No cookie, no fingerprint, no third party.
        </p>

        <div id="statsFigures" class="grid grid-cols-1 md:grid-cols-3 border-y border-rule">
          <div class="fig py-4 md:pr-5">
            <div class="n" id="figViews">{number(@summary.views)}</div>
            <div class="l">views, last {@window} days</div>
          </div>
          <div class="fig py-4 md:px-5 border-t border-hair md:border-t-0 md:border-l md:border-l-hair">
            <div class="n" id="figPeople">{number(@summary.people)}</div>
            <div class="l">people, last {@window} days</div>
          </div>
          <div class="fig py-4 md:px-5 border-t border-hair md:border-t-0 md:border-l md:border-l-hair">
            <div class="n" id="figBusiest">{busiest_number(@summary.busiest)}</div>
            <div class="l">{busiest_label(@summary.busiest)}</div>
          </div>
        </div>

        <h2 class="sec-h">Views, last {@window} days</h2>
        <.day_chart id="dayChart" days={@days} />

        <h2 class="sec-h">Top entries, all time</h2>
        <p :if={@top == []} class="note" id="topEmpty">
          No entry has been read yet. The first reader who opens one puts it here.
        </p>
        <div :if={@top != []} class="overflow-x-auto">
          <table>
            <thead>
              <tr>
                <th>Entry</th>
                <th class="text-right num hidden sm:table-cell">Published</th>
                <th class="text-right num">Views</th>
                <th class="text-right num hidden sm:table-cell">Comments</th>
                <th class="text-right"><span class="sr">Details</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @top} id={"top-#{row.article.id}"}>
                <td>{Articles.display_title(row.article)}</td>
                <td class="text-right num hidden sm:table-cell">{row.article.publish_date}</td>
                <td class="text-right num">{number(row.views)}</td>
                <td class="text-right num hidden sm:table-cell">
                  {Map.get(@comment_counts, row.article.id, 0)}
                </td>
                <td class="text-right">
                  <.link class="link" navigate={~p"/admin/texts/#{row.article.id}?tab=stats"}>
                    details
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h2 class="sec-h">Referrers, last {@window} days</h2>
        <p :if={@referrers == []} class="note" id="referrersEmpty">
          Nothing counted yet, so there is nowhere readers came from.
        </p>
        <.referrer_table :if={@referrers != []} id="referrers" rows={@referrers} />
        <p :if={length(@referrers) == Stats.rows()} class="note mt-[10px]" id="referrersCapped">
          The {Stats.rows()} biggest sources. What the shares leave short of a
          hundred came from the others.
        </p>

        <h2 :if={@pages != []} class="sec-h">Other addresses, last {@window} days</h2>
        <div :if={@pages != []} class="overflow-x-auto">
          <table id="otherPages">
            <thead>
              <tr>
                <th>Address</th>
                <th class="text-right num">Views</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @pages}>
                <td>{row.path}</td>
                <td class="text-right num">{number(row.views)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={length(@pages) == Stats.rows()} class="note mt-[10px]" id="pagesCapped">
          The {Stats.rows()} most read addresses.
        </p>

        <p class="note mt-[22px]" id="statsRule">
          A reader is a number for one day: their address and their browser
          line, mixed with a secret this server draws every morning and
          forgets every night. Nothing links the same reader to two days, so
          somebody who reads every week counts as one person each time. A
          page counts once per reader every half hour, and what says it is a
          bot, or only fetched the page ahead, counts not at all.
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp busiest_number(nil), do: "0"
  defp busiest_number({_day, views}), do: number(views)

  defp busiest_label(nil), do: "busiest day"
  defp busiest_label({day, _views}), do: "busiest day, #{day_label(day)}"
end
