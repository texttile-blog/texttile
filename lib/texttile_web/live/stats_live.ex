defmodule TexttileWeb.StatsLive do
  @moduledoc """
  The Stats overview: how many people read the blog, and what they
  read.

  One window at a time, picked in the address: the last 7, 30, 90 or
  365 days, or all time. Three figures for it, a bar per day, week or
  month of it, the most read entries in it, where the readers came
  from and the addresses that are no entry. A clicked bar opens what
  was read in those days under the chart, and the address remembers
  the bar too, so the back button and a copied link both land on it.

  The screen shows what it loaded. Numbers that move while somebody
  watches them are a distraction, not a report.
  """

  use TexttileWeb, :live_view

  import TexttileWeb.StatsComponents

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Stats

  @windows [7, 30, 90, 365, :all]
  @default 30

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Stats"))
     |> assign(:comment_counts, Comments.count_map())}
  end

  # The address holds the whole state: `days` is the window and `day`
  # the bar that is open. Both are read anew on every patch, so a click
  # and a typed address end up on the same screen.
  def handle_params(params, _uri, socket) do
    days = window_days(params["days"])
    window = Stats.window(days)
    series = Stats.series(window)

    {:noreply,
     socket
     |> assign(:days, days)
     |> assign(:step, Stats.step(window))
     |> assign(:summary, Stats.summary(window))
     |> assign(:series, series)
     |> assign(:top, Stats.top_articles(window, 20))
     |> assign(:referrers, Stats.referrers(window))
     |> assign(:pages, Stats.other_pages(window))
     |> assign_bar(window, params["day"])}
  end

  defp window_days("all"), do: :all

  defp window_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {n, ""} when n in @windows -> n
      _ -> @default
    end
  end

  defp window_days(_days), do: @default

  defp assign_bar(socket, window, day) do
    bar =
      with day when is_binary(day) <- day,
           {:ok, date} <- Date.from_iso8601(day) do
        Stats.bar(window, date)
      else
        _ -> nil
      end

    socket
    |> assign(:bar, bar)
    |> assign(:bar_summary, bar && Stats.summary(bar))
    |> assign(:bar_pages, bar && Stats.pages_read(bar))
    |> assign(:bar_referrers, bar && Stats.referrers(bar))
  end

  # A bar is clicked open and clicked shut. The address changes, the
  # rest follows in `handle_params`.
  def handle_event("pick", %{"day" => day}, socket) do
    open = socket.assigns.bar && Date.to_iso8601(socket.assigns.bar.from)
    day = if day == open, do: nil, else: day
    {:noreply, push_patch(socket, to: stats_path(socket.assigns.days, day))}
  end

  defp stats_path(days, nil), do: ~p"/admin/stats?days=#{days}"
  defp stats_path(days, day), do: ~p"/admin/stats?days=#{days}&day=#{day}"

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Stats")}
      active="stats"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="admin-col">
        <h1 class="page-h">{gettext("Stats")}</h1>
        <%!-- a phone leaves the line out: with the heading in the bar it
             would open the screen as a stray subtitle, and the note at
             the foot says how a reader is counted --%>
        <p class="lead max-sm:hidden" id="statsSub">
          {gettext("Counted by this server alone. No cookie, no fingerprint, no third party.")}
        </p>

        <div id="statsWindows" class="flex flex-wrap gap-1 mb-5">
          <.link
            :for={days <- windows()}
            id={"win-#{days}"}
            patch={stats_path(days, nil)}
            class={["seg-b", @days == days && "on"]}
          >
            {window_name(days)}
          </.link>
        </div>

        <%!-- no rule over the figures: the window switch above them is a row
             of tabs like every other, its line under the open one alone --%>
        <div id="statsFigures" class="grid grid-cols-3">
          <div class="fig py-4 pr-3 md:pr-5">
            <div class="n" id="figViews">{number(@summary.views)}</div>
            <%!-- the window is named once, by the switch over the figures;
                 the change against the window before stands on a line
                 of its own, so a phone never breaks a label in two --%>
            <div class="l">
              {gettext("views")}<span class="block">{moved(@summary.views, @summary.before, :views)}</span>
            </div>
          </div>
          <div class="fig py-4 pr-3 md:pr-5">
            <div class="n" id="figPeople">{number(@summary.people)}</div>
            <div class="l">
              {gettext("people")}<span class="block">{moved(@summary.people, @summary.before, :people)}</span>
            </div>
          </div>
          <div class="fig py-4 pr-3 md:pr-5">
            <div class="n" id="figBusiest">{busiest_number(@summary.busiest)}</div>
            <div class="l">
              <%!-- one line, so the three figures end together --%>
              <span class="whitespace-nowrap">
                {gettext("busiest day")}<span
                  :if={@summary.busiest}
                  id="figBusiestDay"
                >, {busiest_day(@summary.busiest)}</span>
              </span>
            </div>
          </div>
        </div>

        <h2 class="sec-h">{gettext("Views")}{step_label(@step)}</h2>
        <.day_chart id="dayChart" series={@series} step={@step} pick="pick" open={@bar} />
        <p :if={@summary.busiest} class="hint" id="chartKey">
          <%!-- what the dark bar means, and what a click does: two facts,
               two lines --%>
          <span class="block">{gettext("The dark bar is the busiest day.")}</span>
          <span class="block">{gettext("Open a day for its entries and sources.")}</span>
        </p>

        <div :if={@bar} id="barDetail" class="border-l-2 border-ink pl-[14px] mt-4">
          <p class="text-[15px] font-semibold" id="barTitle">
            {span_label(@bar)}
            <span class="text-faint font-normal text-[12.5px]">
              · {ngettext("1 view", "%{count} views", @bar_summary.views)} · {ngettext(
                "1 person",
                "%{count} people",
                @bar_summary.people
              )} ·
              <button
                type="button"
                id="barClose"
                class="link"
                phx-click="pick"
                phx-value-day={@bar.from}
              >
                {gettext("close")}
              </button>
            </span>
          </p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-3">
            <div class="overflow-x-auto">
              <table id="barPages">
                <thead>
                  <tr>
                    <th>{gettext("Read")}</th>
                    <th class="text-right num w-[44px] sm:w-[64px] pl-2 sm:pl-4">
                      {gettext("Views")}
                    </th>
                    <th class="text-right num w-[44px] sm:w-[64px] pl-2 sm:pl-4">
                      {gettext("People")}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @bar_pages}>
                    <td>
                      <.link
                        :if={row.article}
                        class="link"
                        navigate={~p"/admin/texts/#{row.article.id}?tab=stats"}
                      >
                        {Articles.display_title(row.article)}
                      </.link>
                      <span :if={is_nil(row.article)}>{row.path}</span>
                    </td>
                    <td class="text-right num">{number(row.views)}</td>
                    <td class="text-right num">{number(row.people)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.referrer_table id="barReferrers" rows={@bar_referrers} />
          </div>
        </div>

        <h2 class="sec-h">{gettext("Top entries")}</h2>
        <p :if={@top == []} class="note" id="topEmpty">
          {gettext(
            "No entry has been read in these days. The first reader who opens one puts it here."
          )}
        </p>
        <div :if={@top != []} class="overflow-x-auto">
          <table>
            <thead>
              <tr>
                <%!-- the entry takes the free width; the day and the counts
                     are columns of fixed width packed to the right edge, so
                     the data of a row reads as one line --%>
                <th>{gettext("Entry")}</th>
                <th class="num hidden sm:table-cell sm:w-[130px]">{gettext("Date")}</th>
                <th class="text-right num w-[52px] sm:w-[88px] pl-4">{gettext("Views")}</th>
                <th class="text-right num w-[52px] sm:w-[88px] pl-4">{gettext("People")}</th>
                <th class="text-right num hidden sm:table-cell sm:w-[88px] sm:pl-4">
                  {gettext("Comments")}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @top} id={"top-#{row.article.id}"}>
                <%!-- the title is the way to the entry's own numbers --%>
                <td class="pr-5">
                  <%!-- the mark of the state before the title, once per row;
                       a phone, which has no Date and Comments columns, says
                       them on a line under the title --%>
                  <span class="flex items-baseline">
                    <i class={["mk flex-none", row.article.status]} aria-hidden="true"></i>
                    <span class="min-w-0">
                      <.link class="link" navigate={~p"/admin/texts/#{row.article.id}?tab=stats"}>
                        {Articles.display_title(row.article)}
                      </.link>
                      <span class="sm:hidden block text-[12.5px] text-faint num">
                        <.published_cell article={row.article} />
                        · {ngettext(
                          "1 comment",
                          "%{count} comments",
                          Map.get(@comment_counts, row.article.id, 0)
                        )}
                      </span>
                    </span>
                  </span>
                </td>
                <td class="num hidden sm:table-cell">
                  <.published_cell article={row.article} />
                </td>
                <td class="text-right num">{number(row.views)}</td>
                <td class="text-right num people">{number(row.people)}</td>
                <td class="text-right num hidden sm:table-cell">
                  {Map.get(@comment_counts, row.article.id, 0)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h2 class="sec-h">{gettext("Referrers")}</h2>
        <p :if={@referrers == []} class="note" id="referrersEmpty">
          {gettext("Nothing counted yet, so there is nowhere readers came from.")}
        </p>
        <.referrer_table :if={@referrers != []} id="referrers" rows={@referrers} />
        <p :if={length(@referrers) == Stats.rows()} class="note mt-[10px]" id="referrersCapped">
          {gettext(
            "The %{rows} biggest sources. What the shares leave short of a hundred came from the others.",
            rows: Stats.rows()
          )}
        </p>

        <h2 :if={@pages != []} class="sec-h">{gettext("Other addresses")}</h2>
        <div :if={@pages != []} class="overflow-x-auto">
          <table id="otherPages">
            <thead>
              <tr>
                <th>{gettext("Address")}</th>
                <th class="text-right num">{gettext("Views")}</th>
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
          {gettext("The %{rows} most read addresses.", rows: Stats.rows())}
        </p>

        <p class="note mt-[22px]" id="statsRule">
          {gettext(
            "A reader is a new number each day, made with a secret the server forgets every night, so nothing links two days. A page counts once per reader every half hour. Bots and prefetches do not count."
          )}
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp windows, do: @windows

  defp window_name(7), do: gettext("7 days")
  defp window_name(30), do: gettext("30 days")
  defp window_name(90), do: gettext("90 days")
  defp window_name(365), do: gettext("Year")
  defp window_name(:all), do: gettext("All time")

  # The headings say what, the switch over the figures says how long.
  # A bar that is no day says so next to the heading.
  defp step_label(:day), do: nil
  defp step_label(:week), do: gettext(", by week")
  defp step_label(:month), do: gettext(", by month")

  # How the figure moved against the window before, in whole percent.
  # Nothing before, or nothing to compare with, says nothing.
  defp moved(_now, nil, _key), do: nil

  defp moved(now, before, key) do
    case Map.fetch!(before, key) do
      0 -> nil
      was -> signed(round((now - was) / was * 100)) <> "\u00a0%"
    end
  end

  defp signed(n) when n > 0, do: "+#{n}"
  defp signed(n), do: Integer.to_string(n)

  defp busiest_number(nil), do: "0"
  defp busiest_number({_day, views}), do: number(views)

  defp busiest_day({day, _views}), do: day_label(day)

  # The day an entry went out, or the word Draft in grey while it has
  # none; the mark of the state stands before the title.
  attr :article, :any, required: true

  defp published_cell(%{article: %{status: "draft"}} = assigns) do
    ~H"""
    <span class="whitespace-nowrap text-faint">
      {gettext("Draft")}
    </span>
    """
  end

  defp published_cell(%{article: %{publish_date: nil}} = assigns), do: ~H""

  defp published_cell(assigns) do
    ~H"""
    <span class="whitespace-nowrap">
      {Texttile.I18n.format_short_date(@article.publish_date)}
    </span>
    """
  end
end
