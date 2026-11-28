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
     # the comments a reader sees under the entry: the same number the
     # entry page and the cards show, so the screens never disagree
     |> assign(:comment_counts, Comments.reader_count_map())}
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
  def handle_event("pick", %{"day" => ""}, socket) do
    {:noreply, push_patch(socket, to: stats_path(socket.assigns.days, nil))}
  end

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
      waiting={@waiting_comments}
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

        <div id="statsWindows" class="flex flex-wrap gap-[18px] border-b border-hair mb-5">
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
        <div id="statsFigures" class="flex flex-wrap gap-x-7 sm:gap-x-16 gap-y-2">
          <div class="fig py-4">
            <div class="n" id="figViews">{number(@summary.views)}</div>
            <%!-- the window is named once, by the switch over the figures;
                 the change against the window before stands on a line
                 of its own, so a phone never breaks a label in two --%>
            <div class="l">
              {gettext("views")}<span class="block">{moved(@summary.views, @summary.before, :views)}</span>
            </div>
          </div>
          <div class="fig py-4">
            <div class="n" id="figPeople">{number(@summary.people)}</div>
            <div class="l">
              {gettext("reader-days")}<span class="block">{moved(
                @summary.people,
                @summary.before,
                :people
              )}</span>
            </div>
          </div>
          <div class="fig py-4">
            <div class="n" id="figBusiest">{busiest_number(@summary.busiest)}</div>
            <div class="l">
              <span id="figBusiestDay" class="peak-day-label">
                <i :if={@summary.busiest} class="peak-swatch" aria-hidden="true"></i>{gettext(
                  "peak day"
                )}<span :if={@summary.busiest}> · {busiest_day(@summary.busiest)}</span>
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center justify-between gap-3 mt-5 sm:mt-6 mb-2.5">
          <h2 class="sec-h !m-0">{gettext("Views")}{step_label(@step)}</h2>
          <%!-- Day inspection works via the picker on both phone and desktop,
               and by clicking any bar directly on desktop. --%>
          <form :if={@summary.busiest} phx-change="pick" id="dayPickerForm" class="flex-none ml-auto">
            <label for="dayPick" class="sr">{gettext("Inspect a day")}</label>
            <select
              id="dayPick"
              name="day"
              class="!w-auto !min-w-0 h-[40px] sm:h-[34px] !py-0 text-[13.5px] sm:text-[13px]"
            >
              <option value="">{gettext("Inspect a day")}</option>
              <option
                :for={bar <- Enum.reverse(@series)}
                value={Date.to_iso8601(bar.from)}
                selected={@bar && @bar.from == bar.from}
              >
                {span_label(bar)} · {ngettext("1 view", "%{count} views", bar.views)}
              </option>
            </select>
          </form>
        </div>
        <.day_chart id="dayChart" series={@series} step={@step} pick="pick" open={@bar} />
        <%!-- how a reader is counted, directly under the chart so the plot
             connects straight to the totals above --%>
        <p class="hint !mt-2.5 mb-0 max-w-[64ch]" id="statsRule">
          {gettext(
            "Views count every page opened. Reader-days count each reader once a day; nobody is followed from one day to the next. Bots are left out."
          )}
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
                      {gettext("Reader-days")}
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
          <table class="toptab">
            <thead>
              <tr>
                <%!-- identical metric order and visual weight across desktop and phone --%>
                <th>{gettext("Entry")}</th>
                <th class="text-right num w-[1%] whitespace-nowrap pl-2 sm:pl-6">
                  {gettext("Views")}
                </th>
                <th class="text-right num people w-[1%] whitespace-nowrap pl-2.5 sm:pl-6">
                  {gettext("Reader-days")}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @top} id={"top-#{row.article.id}"}>
                <%!-- the title is the way to the entry's own numbers --%>
                <td class="pr-1.5 sm:pr-4">
                  <%!-- the mark of the state before the title, once per row --%>
                  <span class="flex items-baseline">
                    <%!-- live is what a read entry almost always is, so only
                         another state earns its mark --%>
                    <i
                      :if={row.article.status != "published"}
                      class={["mk flex-none", row.article.status]}
                      aria-hidden="true"
                    ></i>
                    <span class="min-w-0">
                      <.link
                        class="link font-serif text-[15.5px] sm:text-[16px] font-semibold"
                        navigate={~p"/admin/texts/#{row.article.id}?tab=stats"}
                      >
                        {Articles.display_title(row.article)}
                      </.link>
                      <span class="block text-[12.5px] text-dim num mt-[2px]">
                        <.published_cell article={row.article} />
                        <span :if={Map.get(@comment_counts, row.article.id, 0) > 0}>
                          · {ngettext(
                            "1 comment",
                            "%{count} comments",
                            Map.get(@comment_counts, row.article.id, 0)
                          )}
                        </span>
                      </span>
                    </span>
                  </span>
                </td>
                <td class="text-right num">{number(row.views)}</td>
                <td class="text-right num people">{number(row.people)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="grid grid-cols-1 items-start">
          <div>
            <h2 class="sec-h !mt-10">{gettext("Referrers")}</h2>
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
          </div>

          <div :if={@pages != []}>
            <h2 class="sec-h !mt-10">{gettext("Other pages")}</h2>
            <div class="overflow-x-auto">
              <table id="otherPages">
                <thead>
                  <tr>
                    <th>{gettext("Address")}</th>
                    <th class="text-right num">{gettext("Views")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @pages}>
                    <td>
                      <%= if row.path == "/" do %>
                        {gettext("Front page")}
                      <% else %>
                        <span class="font-mono text-[13px]">{row.path}</span>
                      <% end %>
                    </td>
                    <td class="text-right num">{number(row.views)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p :if={length(@pages) == Stats.rows()} class="note mt-[10px]" id="pagesCapped">
              {gettext("The %{rows} most read addresses.", rows: Stats.rows())}
            </p>
          </div>
        </div>
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

  defp busiest_day(nil), do: nil
  defp busiest_day({day, _views}), do: Texttile.I18n.format_short_day(day)

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
