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

  @doc """
  The foot of every page: the way onto the newsletter, the site name,
  and the door to the desk. The form carries the same invisible spam
  filters as the comment form - a stamp of the moment it was drawn,
  and a honeypot no person ever sees.
  """
  attr :current_scope, :any, default: nil

  def site_foot(assigns) do
    assigns =
      assign(
        assigns,
        :newsletter_token,
        Phoenix.Token.sign(TexttileWeb.Endpoint, "newsletter form", System.system_time(:second))
      )

    ~H"""
    <footer class="border-t border-rule">
      <div class="wrap pt-4">
        <form
          id="newsletter-form"
          action={~p"/newsletter"}
          method="post"
          class="f-foot flex flex-wrap items-center gap-x-3 gap-y-2"
        >
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="t" value={@newsletter_token} />
          <input
            type="text"
            name="website"
            id="nl-hp"
            class="sr"
            tabindex="-1"
            aria-hidden="true"
            autocomplete="off"
          />
          <label for="nl-email" class="text-ink">New texts by mail</label>
          <input
            type="email"
            id="nl-email"
            name="email"
            placeholder="Your email, never shared"
            required
            class="flex-1 min-w-[190px] max-w-[290px] h-[30px] text-[13px]"
          />
          <button class="btn h-[30px]">Subscribe</button>
        </form>
        <div class="f-foot flex flex-wrap items-baseline gap-x-4 gap-y-1.5 pt-3">
          <a href={~p"/"} class="font-semibold text-ink">{site_title()}</a>
          <span class="sp"></span>
          <a :if={@current_scope} id="foot-desk" href={~p"/admin"}>Desk</a>
          <a :if={!@current_scope} id="foot-signin" href={~p"/login"}>Sign in</a>
        </div>
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

  Each of them stands in a link to the original, so a crawler finds the
  file as it came; the script turns that link into the lightbox, which
  shows the reader size named in `data-full`.
  """
  def body_html(article) do
    article.body
    |> Texttile.Markdown.to_html()
    |> link_pictures()
    |> Phoenix.HTML.raw()
  end

  # The markdown renderer writes <img src="/uploads/..."> and nothing
  # else around it, so the wrap is one pass over those tags.
  defp link_pictures(html) do
    Regex.replace(~r{<img([^>]*?)src="/uploads/([^"]+)"([^>]*?)/?>}, html, fn _whole,
                                                                              before,
                                                                              path,
                                                                              rest ->
      ~s(<a class="bodypic" href="/uploads/#{path}" data-full="/renditions/max/#{path}">) <>
        ~s(<img#{before}src="/renditions/1320/#{path}"#{rest} />) <>
        ~s(</a>)
    end)
  end

  @doc """
  Whether a text shows a picture at all: a gallery tile, or one in the
  words. The lightbox shell is only drawn where something can open it.
  """
  def pictures?(article, gallery) do
    gallery != [] or String.contains?(to_string(article.body), "](/uploads/")
  end

  @doc "A date the way the example blog writes one: 2 July 2026."
  def format_date(nil), do: ""

  def format_date(date) do
    "#{date.day} #{Calendar.strftime(date, "%B %Y")}"
  end

  @doc "The lead line of a card, see `Texttile.Articles.lead/1`."
  defdelegate lead(article), to: Articles

  @doc "The heading of the comments block: the count while there is one."
  def comment_heading(0), do: "Comments"
  def comment_heading(1), do: "1 comment"
  def comment_heading(n), do: "#{n} comments"

  @doc """
  The day a comment arrived, the way the example blog writes it: bare
  within the year, with the year once it is another one.
  """
  def comment_when(%DateTime{} = at) do
    date = DateTime.to_date(at)

    if date.year == Date.utc_today().year do
      "#{date.day} #{Calendar.strftime(date, "%B")}"
    else
      format_date(date)
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
