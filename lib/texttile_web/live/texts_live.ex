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
  alias Texttile.Comments
  alias Texttile.Gallery

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
    |> assign(:across_years, list.across_years)
    |> assign(:page, list.page)
    |> assign(:pages, list.pages)
    |> assign(:shown, list.shown)
    |> assign(:articles, list.entries)
    |> assign(:covers, Gallery.previews(list.entries))
    |> assign(:comment_counts, Comments.count_map())
    # which live entries are being rewritten right now. One query for
    # the whole grid: the bodies of every entry are far too much to
    # carry here a second time just to compare them.
    |> assign(:pending, Articles.entries_with_unpublished_changes())
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
    {:noreply, socket |> assign(:page, page) |> load()}
  end

  # The archive narrows the grid to one year, and then to one month of
  # it. `Listing` reads the raw values and drops a month whose year is
  # gone: a month only ever belongs to the year over it.
  def handle_event("period", params, socket) do
    {:noreply,
     socket
     |> assign(:year, params["year"])
     |> assign(:month, params["month"])
     |> assign(:page, 1)
     |> load()}
  end

  def handle_info({:article_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:article_deleted, _id}, socket), do: {:noreply, load(socket)}
  def handle_info({:text_changed, _article}, socket), do: {:noreply, load(socket)}
  def handle_info({:gallery_changed, _id, _meta}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
  # a restore puts a comment back into the count on its card
  def handle_info({:comment_changed, _comment}, socket), do: {:noreply, load(socket)}
  # an import brings a whole conversation with the entry
  def handle_info({:comments_imported, _article_id}, socket), do: {:noreply, load(socket)}
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
              all
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
            <%!-- no count on this row at all: the year over it already
                 says how many the year holds, and twelve numbers in a
                 row is a table, not a line --%>
            <.period
              label={gettext("All months")}
              on={is_nil(@month)}
              all
              phx-click="period"
              phx-value-year={@year}
            />
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
                <span class="cimg empty">{gettext("no images yet")}</span>
              <% end %>
              <span class="ct">{Articles.display_title(article)}</span>
              <span class="cm">
                <span class={["st", article.status]}></span>{card_meta(
                  article,
                  @comment_counts[article.id],
                  article.id in @pending
                )}
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
    "background-image:url('#{Images.url(path, :thumb)}')"
  end

  defp card_meta(article, comment_count, pending?) do
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
          # A live entry that is being rewritten says so here, because
          # this grid is the one place that shows every entry at once
          # and is where somebody looks for what is still open.
          if pending?,
            do: [to_string(article.publish_date), gettext("edited since publishing")],
            else: [to_string(article.publish_date)]
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

    # Who it is by, beside the day. Nil where the account has gone.
    bits =
      case Articles.author_name(article) do
        nil -> bits
        name -> bits ++ [name]
      end

    Enum.join(bits, " · ")
  end
end
