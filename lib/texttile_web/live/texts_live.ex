defmodule TexttileWeb.TextsLive do
  @moduledoc """
  The Entries overview: the full-page grid of cards without boxes, a
  status filter, a search over titles, tags and the entries themselves,
  and the archive of years and months over the grid. The design is the
  round-14 grid; a card wears its entry's preview image
  (`Texttile.Gallery.effective_preview/2`).
  """
  use TexttileWeb, :live_view

  alias Texttile.Articles
  alias Texttile.Images
  alias Texttile.Comments
  alias Texttile.Gallery
  alias Texttile.Settings

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Articles.subscribe_admin()
      Comments.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Entries"))
     |> assign(:filter, "all")
     |> assign(:q, "")
     |> assign(:year, nil)
     |> assign(:month, nil)
     |> assign(:page, 1)
     |> load()}
  end

  defp load(socket) do
    %{filter: filter, q: q} = socket.assigns
    found = Articles.list_articles(filter: filter, search: q)

    # The search and the status filter can empty the year that is open.
    # Then the year lets go, rather than leaving an empty grid behind.
    {year, month} = Articles.settle_period(found, socket.assigns.year, socket.assigns.month)
    {years, months} = Articles.periods(found, year)
    in_period = Enum.filter(found, &Articles.in_period?(&1, year, month))

    # One page size for the whole installation, so the grid an admin
    # works in is cut the same way as the list a reader walks. A text
    # deleted somewhere else can take the last page with it, so the
    # page the screen stands on is held inside what is left.
    per_page = Settings.get(:posts_per_page)
    pages = max(1, ceil(length(in_period) / per_page))
    page = socket.assigns.page |> max(1) |> min(pages)
    articles = Enum.slice(in_period, (page - 1) * per_page, per_page)

    socket
    |> assign(:year, year)
    |> assign(:month, month)
    |> assign(:years, years)
    |> assign(:months, months)
    # what the search and the status filter found across every year: the
    # number "All years" carries, so it counts the way the years do
    |> assign(:across_years, length(found))
    |> assign(:page, page)
    |> assign(:pages, pages)
    # the count over the grid speaks of everything the search found, not
    # of the page it happens to show
    |> assign(:shown, length(in_period))
    |> assign(:articles, articles)
    |> assign(:covers, Gallery.previews(articles))
    |> assign(:comment_counts, Comments.count_map())
    |> assign(:total, length(Articles.list_articles()))
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(:filter, filter) |> assign(:page, 1) |> load()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:q, q) |> assign(:page, 1) |> load()}
  end

  # A step of the pager. Every other way of narrowing the grid starts
  # over on the first page, because the page a reader stood on says
  # nothing about the set they are looking at now.
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:page, number(page) || 1) |> load()}
  end

  # The archive narrows the grid to one year, and then to one month of
  # it. Choosing another year drops the month with it: a month only
  # ever belongs to the year over it.
  def handle_event("period", params, socket) do
    year = number(params["year"])
    month = year && number(params["month"])

    {:noreply,
     socket |> assign(:year, year) |> assign(:month, month) |> assign(:page, 1) |> load()}
  end

  defp number(nil), do: nil
  defp number(""), do: nil

  defp number(raw) do
    case Integer.parse(to_string(raw)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  def handle_info({:article_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:article_deleted, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:text_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:gallery_changed, _id, _meta}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
  # a restore puts a comment back into the count on its card
  def handle_info({:comment_changed, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Entries")}
      active="texts"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[1060px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">{gettext("Entries")}</h1>
          <span class="note num" id="gridCount">{entry_count(@shown, @total)}</span>
          <span class="sp"></span>
          <button class="btn solid" id="new-text" phx-click="new_text">{gettext("New entry")}</button>
        </div>
        <div class="flex items-center gap-3 flex-wrap py-3 mt-[14px] mb-6 border-y border-rule">
          <span class="flex gap-[3px] flex-none" role="group" aria-label={gettext("Filter by status")}>
            <button
              :for={
                {value, label} <- [
                  {"all", gettext("All")},
                  {"published", gettext("Live")},
                  {"draft", gettext("Drafts")}
                ]
              }
              class={["seg-b", @filter == value && "on"]}
              data-f={value}
              phx-click="filter"
              phx-value-filter={value}
            >
              {label}
            </button>
          </span>
          <form id="grid-search" class="contents" phx-change="search" phx-submit="search">
            <input
              type="search"
              name="q"
              value={@q}
              placeholder={gettext("Search title, tags, text")}
              aria-label={gettext("Search entries")}
              autocomplete="off"
              phx-debounce="200"
              class="w-auto grow shrink basis-[240px] min-w-[150px] max-w-[680px] ml-auto"
            />
          </form>
        </div>
        <%!-- the archive: one line of years, and the months of the year
             that is open under it. Only the months that carry entries;
             the counts follow the search and the status filter. --%>
        <nav :if={@years != []} class="periods" id="periods" aria-label={gettext("Archive")}>
          <p class="prow" id="years">
            <.period
              label={gettext("All years")}
              on={is_nil(@year)}
              count={@across_years}
              phx-click="period"
            />
            <.period
              :for={{year, count} <- @years}
              label={year}
              on={@year == year}
              count={count}
              phx-click="period"
              phx-value-year={year}
            />
          </p>
          <p :if={@months != []} class="prow" id="months">
            <.period
              label={gettext("All months")}
              on={is_nil(@month)}
              count={Enum.sum(Enum.map(@months, &elem(&1, 1)))}
              phx-click="period"
              phx-value-year={@year}
            />
            <%!-- no count under a month: twelve numbers in a row is a
                 table, not a line --%>
            <.period
              :for={{month, _count} <- @months}
              label={Articles.month_name(month)}
              on={@month == month}
              phx-click="period"
              phx-value-year={@year}
              phx-value-month={month}
            />
          </p>
        </nav>
        <div
          class="grid items-start gap-y-[22px] gap-x-3 md:gap-y-7 md:gap-x-5 grid-cols-[repeat(auto-fill,minmax(150px,1fr))] md:grid-cols-[repeat(auto-fill,minmax(210px,1fr))]"
          id="cards"
        >
          <.link :for={article <- @articles} class="card" navigate={~p"/admin/texts/#{article}"}>
            <%= if cover = @covers[article.id] do %>
              <span class="cimg" style={cover_bg(cover)}></span>
            <% else %>
              <span class="cimg empty">{gettext("no images yet")}</span>
            <% end %>
            <span class="ct">{Articles.display_title(article)}</span>
            <span class="cm">
              <span class={["st", article.status]}></span>{card_meta(
                article,
                @comment_counts[article.id]
              )}
            </span>
          </.link>
        </div>
        <%!-- the pager under the grid: the reader's three cells, with
             buttons instead of addresses, because this grid is filtered
             by click and not by address --%>
        <nav
          :if={@pages > 1}
          class="f-pager mt-9 pt-4 border-t border-rule"
          id="pager"
          aria-label={gettext("Pages")}
        >
          <span>
            <button
              :if={@page > 1}
              class="btn sm"
              id="prev-page"
              phx-click="page"
              phx-value-page={@page - 1}
            >
              {gettext("Newer")}
            </button>
          </span>
          <span class="note num">
            {gettext("Page %{page} of %{pages}", page: @page, pages: @pages)}
          </span>
          <span>
            <button
              :if={@page < @pages}
              class="btn sm"
              id="next-page"
              phx-click="page"
              phx-value-page={@page + 1}
            >
              {gettext("Older")}
            </button>
          </span>
        </nav>
        <p :if={@articles == []} class="note">
          {if @total == 0,
            do: gettext("No entries yet. New entry starts the first one."),
            else: gettext("Nothing matches. The search covers titles, tags and the entry itself.")}
        </p>
        <%!-- every digit the wordmark menu carries, in the order it
             carries them, so the two never say different things --%>
        <p class="hidden md:block text-[12.5px] text-faint mt-9 pt-[13px] border-t border-hair">
          {gettext("Press a key anywhere to jump:")}
          <span :for={section <- Layouts.sections()} class="whitespace-nowrap">
            <b class="text-dim num">{section.key}</b>
            {section.label} ·
          </span>
          <b class="text-dim">/</b>
          {gettext("search.")}
        </p>
      </div>
    </Layouts.app>
    """
  end

  # A preview can come from a body image, so the path is markdown text;
  # a quote must not break out of the url('...') it lands in.
  defp cover_bg(path) do
    "background-image:url('/renditions/#{Images.thumb_edge()}/#{String.replace(path, "'", "%27")}')"
  end

  defp card_meta(article, comment_count) do
    bits =
      case article.status do
        "draft" ->
          [
            gettext("draft"),
            gettext("last edited %{date}",
              date: Texttile.I18n.format_plain_day(article.updated_at)
            )
          ]

        "scheduled" ->
          [
            if(article.publish_date,
              do: gettext("goes live %{date}", date: article.publish_date),
              else: gettext("scheduled, no date yet")
            )
          ]

        "published" ->
          [to_string(article.publish_date)]
      end

    # The count stands on every card that has one, whatever state the
    # text is in: a text taken off the site keeps the comments it
    # collected, and the overview is where somebody looks for them.
    bits =
      bits ++
        case comment_count do
          nil -> []
          0 -> []
          n -> [ngettext("1 comment", "%{count} comments", n)]
        end

    bits = if article.type == "page", do: [gettext("page") | bits], else: bits
    Enum.join(bits, " · ")
  end
end
