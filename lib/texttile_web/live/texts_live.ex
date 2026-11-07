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
  alias Texttile.Articles.Listing
  alias Texttile.Images
  alias Texttile.Gallery

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Articles.subscribe_admin()
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

    # A text deleted somewhere else can take the last page with it, and
    # the search can empty the year that is open; `Listing` holds the
    # page inside what is left and lets the year go.
    list =
      Listing.assemble(found,
        year: socket.assigns.year,
        month: socket.assigns.month,
        page: socket.assigns.page
      )

    socket
    |> assign(:year, list.year)
    |> assign(:month, list.month)
    |> assign(:years, list.years)
    |> assign(:months, list.months)
    |> assign(:page, list.page)
    |> assign(:pages, list.pages)
    |> assign(:shown, list.shown)
    |> assign(:articles, list.entries)
    |> assign(:covers, Gallery.previews(list.entries))
    # which live entries are being rewritten right now. One query for
    # the whole grid: the bodies of every entry are far too much to
    # carry here a second time just to compare them.
    |> assign(:pending, Articles.entries_with_unpublished_changes())
    |> assign_counts()
  end

  # What each filter holds, written into its tab the way the Comments
  # filters carry theirs; the search and the period narrow the grid,
  # not these.
  defp assign_counts(socket) do
    all = Articles.list_articles()
    count = fn status -> Enum.count(all, &(&1.status == status)) end

    socket
    |> assign(:total, length(all))
    |> assign(:counts, %{
      "all" => length(all),
      "published" => count.("published"),
      "scheduled" => count.("scheduled"),
      "draft" => count.("draft")
    })
  end

  defp initial(article) do
    article
    |> Articles.display_title()
    |> String.trim()
    |> String.first()
    |> to_string()
    |> String.upcase()
  end

  # The status filters in their order. Scheduled stands only while an
  # entry waits for its day (or while it is the open filter).
  defp filters(counts, open) do
    [
      {"all", gettext("All")},
      {"published", gettext("Live")},
      {"scheduled", gettext("Scheduled")},
      {"draft", gettext("Drafts")}
    ]
    |> Enum.filter(fn {value, _} ->
      value != "scheduled" or counts["scheduled"] > 0 or open == "scheduled"
    end)
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
    {:noreply, socket |> assign(:page, page) |> load()}
  end

  # The archive narrows the grid to one year, and then to one month of
  # it. `Listing` reads the raw values and drops a month whose year is
  # gone: a month only ever belongs to the year over it.
  # A year chosen anew opens all of its months; an empty choice is all.
  def handle_event("period", params, socket) do
    year = blank_to_nil(params["year"])
    month = if params["_target"] == ["year"], do: nil, else: blank_to_nil(params["month"])

    {:noreply,
     socket
     |> assign(:year, year)
     |> assign(:month, month)
     |> assign(:page, 1)
     |> load()}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  def handle_info({:article_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:article_deleted, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:text_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:gallery_changed, _id, _meta}, socket), do: {:noreply, load(socket)}
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
      <div class="admin-col">
        <%!-- the counts live in the filters, as on Comments; a line of
             its own speaks only while a search or a period narrows the
             grid --%>
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">{gettext("Entries")}</h1>
          <span :if={@q != "" or @year} class="note num" id="gridCount">
            {entry_count(@shown, @total)}
          </span>
        </div>
        <div class="flex items-center gap-x-3 gap-y-[10px] flex-wrap mt-0 sm:mt-6 mb-3 sm:mb-6">
          <span
            class="flex gap-[3px] max-sm:gap-[6px] flex-none"
            role="group"
            aria-label={gettext("Filter by status")}
          >
            <%!-- Scheduled has a tab only while an entry waits for its
                 day, so the parts always add up to All --%>
            <button
              :for={{value, label} <- filters(@counts, @filter)}
              class={["seg-b", @filter == value && "on"]}
              data-f={value}
              phx-click="filter"
              phx-value-filter={value}
            >
              {label} <span class="num text-faint">{@counts[value]}</span>
            </button>
          </span>
          <div class="flex items-center gap-x-2 sm:gap-x-3 gap-y-[10px] grow basis-full sm:basis-[300px] min-w-0">
            <form id="grid-search" class="contents" phx-change="search" phx-submit="search">
              <input
                type="search"
                name="q"
                value={@q}
                placeholder={gettext("Search")}
                aria-label={gettext("Search entries")}
                autocomplete="off"
                phx-debounce="200"
                class="w-auto grow shrink basis-[160px] min-w-0"
              />
            </form>
            <%!-- the archive, the way the reader's list offers it: a year,
                 then the months of that year that carry entries, each with
                 its count; the counts follow the search and the filter --%>
            <form :if={@years != []} id="periods" phx-change="period" class="flex gap-2 flex-none">
              <span class="pick">
                <select name="year" id="years" aria-label={gettext("Year")}>
                  <option value="">{gettext("All years")}</option>
                  <option :for={{year, count} <- @years} value={year} selected={@year == year}>
                    {year} ({count})
                  </option>
                </select>
              </span>
              <span :if={@months != []} class="pick">
                <select name="month" id="months" aria-label={gettext("Month")}>
                  <option value="">{gettext("All months")}</option>
                  <option :for={{month, _count} <- @months} value={month} selected={@month == month}>
                    {Texttile.I18n.month_name(month)}
                  </option>
                </select>
              </span>
            </form>
            <%!-- the one primary action ends the row of tools, on a phone
                 as on a desk, so it never needs a row of its own --%>
            <button class="btn solid flex-none" id="new-text" phx-click="new_text">
              {gettext("New entry")}
            </button>
          </div>
        </div>
        <div
          class="grid items-start gap-y-0 sm:gap-y-[26px] gap-x-4 md:gap-y-8 md:gap-x-5 grid-cols-1 sm:grid-cols-[repeat(auto-fill,minmax(170px,1fr))] md:grid-cols-[repeat(auto-fill,minmax(210px,1fr))]"
          id="cards"
        >
          <%!-- The card is one link to the editor, so the way to the
               zip cannot stand inside it: it is a link of its own,
               laid over the corner of the picture. It shows itself on
               hover and on focus, and stands quietly on a touch
               screen, which has no hover to wait for. --%>
          <div :for={article <- @articles} class="card-slot">
            <.link class="card" navigate={~p"/admin/texts/#{article}"}>
              <%= if cover = @covers[article.id] do %>
                <span class="cimg" style={cover_bg(cover)}></span>
              <% else %>
                <%!-- an entry of words alone shows its opening words, and
                     an empty one says what is missing. The small square
                     of the phone list is the same quiet box, empty. --%>
                <span class="cimg empty">
                  <span :if={Articles.lead(article) != ""} class="cx">
                    {Articles.lead(article, 240)}
                  </span>
                  <%!-- the small square of the phone list holds the first
                       letter of the title, set large: words at that size
                       could not be read --%>
                  <span class="ci" aria-hidden="true">{initial(article)}</span>
                  <span :if={Articles.lead(article) == ""} class="cn">
                    {gettext("no images yet")}
                  </span>
                </span>
              <% end %>
              <span class="ct">{Articles.display_title(article)}</span>
              <%!-- the state and its day on the left, who it is by on the
                   right: two facts, two ends of the line. A narrow card
                   wraps the line between the facts, never inside a day. --%>
              <span class="cm">
                <%!-- a bit holds no whitespace of the template: the browser
                     would carry a space of a nowrap span over to the gap
                     between two bits and refuse to break there --%>
                <span class="bits">
                  <%= for {bit, i} <- card_meta(article, article.id in @pending) do %>
                    <span class="whitespace-nowrap bit" phx-no-format><span :if={i == 0} class={["st", article.status]}></span>{bit}</span>
                  <% end %>
                </span>
                <span :if={article.user} class="by">{admin_name(article.user)}</span>
              </span>
            </.link>
            <a
              class="card-get"
              id={"export-#{article.id}"}
              href={~p"/admin/texts/#{article}/export"}
              download
              title={gettext("Export as a zip")}
              aria-label={gettext("Export %{title} as a zip", title: Articles.display_title(article))}
            >
              <.down_icon />
            </a>
          </div>
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
      </div>
    </Layouts.app>
    """
  end

  # A preview can come from a body image, so the path is markdown text;
  # a quote must not break out of the url('...') it lands in.
  defp cover_bg(path) do
    "background-image:url('#{Images.url(path, :thumb)}')"
  end

  # The facts of a card's line, in order: the state with its day, and
  # "page" in front of them for a page.
  # The line under a card's title: the state as a word, then the day,
  # then what else is true. Every row starts the same way, with the
  # state, so a column of cards reads down one vocabulary.
  defp card_meta(article, pending?) do
    day =
      case article.status do
        "draft" -> Texttile.I18n.format_short_date(DateTime.to_date(article.updated_at))
        _status -> article.publish_date && Texttile.I18n.format_short_date(article.publish_date)
      end

    state =
      case article.status do
        "draft" -> gettext("Draft")
        "scheduled" -> gettext("Scheduled")
        "published" -> gettext("Live")
      end

    # A live entry that is being rewritten says so here, because this
    # grid is the one place that shows every entry at once and is where
    # somebody looks for what is still open.
    bits =
      [
        state,
        article.type == "page" && gettext("page"),
        day || gettext("no date yet"),
        pending? && gettext("edited since publishing")
      ]
      |> Enum.filter(& &1)

    # each bit with its place, so the template can hang the state mark
    # on the first; the separators are the stylesheet's
    Enum.with_index(bits)
  end
end
