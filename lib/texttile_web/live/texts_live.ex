defmodule TexttileWeb.TextsLive do
  @moduledoc """
  The Texts overview: the full-page grid of cards without boxes, a
  status filter, a search over titles, tags and the texts themselves.
  The design is the round-14 grid; a card wears its text's preview
  image (`Texttile.Gallery.effective_preview/2`).
  """
  use TexttileWeb, :live_view

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Gallery

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Articles.subscribe_desk()
      Comments.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Texts")
     |> assign(:filter, "all")
     |> assign(:q, "")
     |> load()}
  end

  defp load(socket) do
    %{filter: filter, q: q} = socket.assigns
    articles = Articles.list_articles(filter: filter, search: q)

    socket
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
      crumb="Texts"
      active="texts"
      others={@others}
    >
      <:bar>
        <%!-- the door to the blog itself, at the end of the bar --%>
        <a
          class="text-[12.5px] text-dim hover:text-accent whitespace-nowrap flex-none"
          id="bar-view-site"
          href={~p"/"}
        >
          View site
        </a>
      </:bar>
      <div class="max-w-[1060px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">Texts</h1>
          <span class="note num" id="gridCount">{grid_count(@articles, @total)}</span>
          <span class="sp"></span>
          <button class="btn solid" id="new-text" phx-click="new_text">New text</button>
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
              aria-label="Search texts"
              autocomplete="off"
              phx-debounce="200"
              class="w-auto grow shrink basis-[240px] min-w-[150px] max-w-[680px] ml-auto"
            />
          </form>
        </div>
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
            do: "No texts yet. New text starts the first one.",
            else: "Nothing matches. The search covers titles, tags and the text itself."}
        </p>
        <p class="hidden md:block text-[12.5px] text-faint mt-9 pt-[13px] border-t border-hair">
          Press a key anywhere to jump: <b class="text-dim num">1</b>
          New text · <b class="text-dim num">2</b>
          Texts · <b class="text-dim num">9</b>
          Settings · <b class="text-dim">/</b>
          search. The keys sleep while you are typing in a field.
        </p>
      </div>
    </Layouts.app>
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
      "#{total} #{if total == 1, do: "text", else: "texts"}"
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
          [to_string(article.publish_date)] ++
            case comment_count do
              nil -> []
              1 -> ["1 comment"]
              n -> ["#{n} comments"]
            end
      end

    bits = if article.type == "page", do: ["page" | bits], else: bits
    Enum.join(bits, " · ")
  end
end
