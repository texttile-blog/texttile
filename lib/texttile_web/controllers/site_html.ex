defmodule TexttileWeb.SiteHTML do
  @moduledoc """
  The reader pages, in the design of the marketing-round-2 example
  blog: the sticky reader header with the site menu, the cards of the
  text list, the serif article column with its square gallery, the tag
  archives, and the footer on the bottom edge of the window.
  """
  use TexttileWeb, :html

  alias Texttile.Articles

  embed_templates "site_html/*"

  @doc """
  The header every reader page wears: the mark and the site name, the
  site description as it stands in Settings, then the menu the app
  builds out of its pages - Home when a fixed page is the front door,
  Blog for the list, then every published page by publish date.
  """
  attr :active, :any, default: nil
  attr :home_page, :any, default: nil
  attr :menu_pages, :list, default: []

  def site_head(assigns) do
    assigns =
      assigns
      |> assign(:brand, %{title: site_title(), logo: Texttile.Settings.get(:logo)})
      |> assign(:desc, String.trim(Texttile.Settings.get(:site_description)))

    ~H"""
    <header class="site-head">
      <a class="site-mark" href={~p"/"}>
        <img
          :if={@brand.logo}
          src={"/uploads/#{@brand.logo}"}
          alt=""
          class="h-[21px] w-auto max-w-[84px] object-contain"
        />
        <Layouts.mark :if={!@brand.logo} size={21} />
        {@brand.title}
      </a>
      <span :if={@desc != ""} class="site-desc">{@desc}</span>
      <nav class="site-nav" aria-label="Site">
        <a :if={@home_page} id="menu-home" href={~p"/"} aria-current={@active == :home && "page"}>
          Home
        </a>
        <a
          id="menu-texts"
          href={if @home_page, do: ~p"/texts", else: ~p"/"}
          aria-current={@active == :texts && "page"}
        >
          Blog
        </a>
        <a
          :for={page <- @menu_pages}
          id={"menu-page-#{page.id}"}
          href={Articles.public_path(page)}
          aria-current={@active == page.id && "page"}
        >
          {Articles.display_title(page)}
        </a>
      </nav>
    </header>
    """
  end

  @doc "The foot of every page: the site name, and the door to the desk."
  attr :current_scope, :any, default: nil

  def site_foot(assigns) do
    ~H"""
    <footer class="border-t border-rule">
      <div class="wrap f-foot flex flex-wrap items-baseline gap-x-4 gap-y-1.5 pt-4 pb-7">
        <a href={~p"/"} class="font-semibold text-ink">{site_title()}</a>
        <span class="sp"></span>
        <a :if={@current_scope} id="foot-desk" href={~p"/admin"}>Desk</a>
        <a :if={!@current_scope} id="foot-signin" href={~p"/login"}>Sign in</a>
      </div>
    </footer>
    """
  end

  @doc "The card of the desk's Texts grid, drawn for a reader."
  attr :article, :any, required: true
  attr :preview, :any, default: nil

  def card(assigns) do
    ~H"""
    <div class="card-wrap">
      <a class="card" id={"text-#{@article.id}"} href={Articles.public_path(@article)}>
        <%!-- every card wears a square, so the grid keeps its rows: the
             picture when there is one, the quiet mark when there is none --%>
        <span :if={@preview} class="cimg">
          <img src={"/renditions/640/#{@preview}"} alt="" loading="lazy" />
        </span>
        <span :if={!@preview} class="cimg blank" aria-hidden="true">
          <Layouts.mark size={34} />
        </span>
        <span class="ct">{Articles.display_title(@article)}</span>
      </a>
      <p class="cm num">{format_date(@article.publish_date)}</p>
      <p :if={lead(@article) != ""} class="clead">{lead(@article)}</p>
      <p :if={Articles.tag_list(@article) != []} class="ctags">
        <a :for={tag <- Articles.tag_list(@article)} class="ctag" href={~p"/tags/#{tag}"}>
          #{tag}
        </a>
      </p>
    </div>
    """
  end

  @doc """
  The body of a text as HTML. Inline pictures leave the original file
  alone and travel as a rendition sized for the reading column - 1320,
  which is the 660px measure on a dense screen - never the full file.
  """
  def body_html(article) do
    article.body
    |> Texttile.Markdown.to_html()
    |> String.replace(~s(src="/uploads/), ~s(src="/renditions/1320/))
    |> Phoenix.HTML.raw()
  end

  @doc "A date the way the example blog writes one: 2 July 2026."
  def format_date(nil), do: ""

  def format_date(date) do
    "#{date.day} #{Calendar.strftime(date, "%B %Y")}"
  end

  @doc """
  The lead line of a card: the first real paragraph of the text, the
  markdown stripped, cut at a word before 160 characters.
  """
  def lead(article) do
    article.body
    |> to_string()
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.trim/1)
    |> Enum.find("", fn block ->
      block != "" and not String.starts_with?(block, "#") and
        not Regex.match?(~r/\A!\[[^\]]*\]\([^)]*\)\z/, block)
    end)
    |> strip_markdown()
    |> shorten(160)
  end

  defp strip_markdown(text) do
    text
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, "")
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[*_`>]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp shorten(text, max) do
    if String.length(text) <= max do
      text
    else
      # the slice ends mid-word, so the broken tail goes - unless the
      # cut is one single word, which stays as it is
      cut = String.slice(text, 0, max)

      head =
        case String.split(cut, " ") do
          [_single] -> cut
          words -> words |> Enum.drop(-1) |> Enum.join(" ")
        end

      head <> "…"
    end
  end

  @doc "What the count beside the search says: all of it, or n of all."
  def count_label(shown, total) do
    if shown == total do
      "#{total} #{if total == 1, do: "text", else: "texts"}"
    else
      "#{shown} of #{total}"
    end
  end

  defdelegate site_title, to: Texttile.Settings
end
