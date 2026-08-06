defmodule TexttileWeb.TextsLive do
  @moduledoc """
  The Texts overview: the full-page grid of cards without boxes, a
  status filter, a search over titles, tags and the texts themselves.
  The design is the round-14 grid; a card wears the oldest gallery
  image of its text.
  """
  use TexttileWeb, :live_view

  alias Texttile.Articles
  alias Texttile.Gallery

  def mount(_params, _session, socket) do
    if connected?(socket), do: Articles.subscribe_desk()

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
    |> assign(:covers, Gallery.cover_paths(Enum.map(articles, & &1.id)))
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
          <.link :for={article <- @articles} class="card" navigate={~p"/texts/#{article}"}>
            <%= if cover = @covers[article.id] do %>
              <span class="cimg" style={"background-image:url('/desk/renditions/320/#{cover}')"}>
              </span>
            <% else %>
              <span class="cimg empty">no images yet</span>
            <% end %>
            <span class="ct">{Articles.display_title(article)}</span>
            <span class="cm">
              <span class={["st", article.status]}></span>{card_meta(article)}
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

  defp grid_count(articles, total) do
    shown = length(articles)

    if shown == total do
      "#{total} #{if total == 1, do: "text", else: "texts"}"
    else
      "#{shown} of #{total}"
    end
  end

  defp card_meta(article) do
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

    bits = if article.type == "page", do: ["page" | bits], else: bits
    Enum.join(bits, " · ")
  end
end
