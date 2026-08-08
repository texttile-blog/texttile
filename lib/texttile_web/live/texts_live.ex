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
  alias Texttile.Comments
  alias Texttile.Gallery

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Articles.subscribe_admin()
      Comments.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Entries")
     |> assign(:filter, "all")
     |> assign(:q, "")
     |> assign(:year, nil)
     |> assign(:month, nil)
     |> load()}
  end

  defp load(socket) do
    %{filter: filter, q: q} = socket.assigns
    found = Articles.list_articles(filter: filter, search: q)

    # The search and the status filter can empty the year that is open.
    # Then the year lets go, rather than leaving an empty grid behind.
    {year, month} = Articles.settle_period(found, socket.assigns.year, socket.assigns.month)
    {years, months} = Articles.periods(found, year)
    articles = Enum.filter(found, &Articles.in_period?(&1, year, month))

    socket
    |> assign(:year, year)
    |> assign(:month, month)
    |> assign(:years, years)
    |> assign(:months, months)
    |> assign(:articles, articles)
    |> assign(:covers, Gallery.previews(articles))
    |> assign(:comment_counts, Comments.count_map())
    |> assign(:total, length(Articles.list_articles()))
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:q, q) |> load()}
  end

  # The archive narrows the grid to one year, and then to one month of
  # it. Choosing another year drops the month with it: a month only
  # ever belongs to the year over it.
  def handle_event("period", params, socket) do
    year = number(params["year"])
    month = year && number(params["month"])

    {:noreply, socket |> assign(:year, year) |> assign(:month, month) |> load()}
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
      crumb="Entries"
      active="texts"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[1060px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">Entries</h1>
          <span class="note num" id="gridCount">{grid_count(@articles, @total)}</span>
          <span class="sp"></span>
          <button class="btn solid" id="new-text" phx-click="new_text">New entry</button>
        </div>
        <div class="flex items-center gap-3 flex-wrap py-3 mt-[14px] mb-6 border-y border-rule">
          <span class="flex gap-[3px] flex-none" role="group" aria-label="Filter by status">
            <button
              :for={{value, label} <- [{"all", "All"}, {"published", "Live"}, {"draft", "Drafts"}]}
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
              placeholder="Search title, tags, text"
              aria-label="Search entries"
              autocomplete="off"
              phx-debounce="200"
              class="w-auto grow shrink basis-[240px] min-w-[150px] max-w-[680px] ml-auto"
            />
          </form>
        </div>
        <%!-- the archive: one line of years, and the months of the year
             that is open under it. Only the months that carry entries;
             the counts follow the search and the status filter. --%>
        <nav :if={@years != []} class="periods" id="periods" aria-label="Archive">
          <p class="prow" id="years">
            <.period label="All years" on={is_nil(@year)} count={@total} />
            <.period
              :for={{year, count} <- @years}
              label={year}
              year={year}
              on={@year == year}
              count={count}
            />
          </p>
          <p :if={@months != []} class="prow" id="months">
            <.period
              label="All months"
              year={@year}
              on={is_nil(@month)}
              count={Enum.sum(Enum.map(@months, &elem(&1, 1)))}
            />
            <%!-- no count under a month: twelve numbers in a row is a
                 table, not a line --%>
            <.period
              :for={{month, _count} <- @months}
              label={Articles.month_name(month)}
              year={@year}
              month={month}
              on={@month == month}
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
              <span class="cimg empty">no images yet</span>
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
        <p :if={@articles == []} class="note">
          {if @total == 0,
            do: "No entries yet. New entry starts the first one.",
            else: "Nothing matches. The search covers titles, tags and the entry itself."}
        </p>
        <%!-- every digit the wordmark menu carries, in the order it
             carries them, so the two never say different things --%>
        <p class="hidden md:block text-[12.5px] text-faint mt-9 pt-[13px] border-t border-hair">
          Press a key anywhere to jump:
          <span :for={section <- Layouts.sections()} class="whitespace-nowrap">
            <b class="text-dim num">{section.key}</b>
            {section.label} ·
          </span>
          <b class="text-dim">/</b>
          search.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @doc """
  One word of the archive: a year, a month, or the "all" that lets go
  of one. The open one says so and stops answering a click, so nothing
  in the row leads to the grid that already stands there.
  """
  attr :label, :any, required: true
  attr :on, :boolean, default: false
  attr :year, :any, default: nil
  attr :month, :any, default: nil
  attr :count, :any, default: nil

  def period(assigns) do
    ~H"""
    <span :if={@on} class="per on" aria-current="true">
      {@label}<span :if={@count} class="cnt">{@count}</span>
    </span>
    <button
      :if={!@on}
      type="button"
      class="per"
      phx-click="period"
      phx-value-year={@year}
      phx-value-month={@month}
    >
      {@label}<span :if={@count} class="cnt">{@count}</span>
    </button>
    """
  end

  # A preview can come from a body image, so the path is markdown text;
  # a quote must not break out of the url('...') it lands in.
  defp cover_bg(path) do
    "background-image:url('/renditions/320/#{String.replace(path, "'", "%27")}')"
  end

  defp grid_count(articles, total) do
    shown = length(articles)

    if shown == total do
      "#{total} #{if total == 1, do: "entry", else: "entries"}"
    else
      "#{shown} of #{total}"
    end
  end

  defp card_meta(article, comment_count) do
    bits =
      case article.status do
        "draft" ->
          ["draft", "last edited #{Calendar.strftime(article.updated_at, "%Y-%m-%d")}"]

        "scheduled" ->
          [
            if(article.publish_date,
              do: "goes live #{article.publish_date}",
              else: "scheduled, no date yet"
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
          1 -> ["1 comment"]
          n -> ["#{n} comments"]
        end

    bits = if article.type == "page", do: ["page" | bits], else: bits
    Enum.join(bits, " · ")
  end
end
