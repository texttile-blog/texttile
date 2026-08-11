defmodule TexttileWeb.SiteHTML do
  @moduledoc """
  The reader pages, in the design of the marketing-round-2 example
  blog: the sticky reader header with the site menu, the cards of the
  text list, the serif article column with its square gallery, the tag
  archives, and the footer on the bottom edge of the window.
  """
  use TexttileWeb, :html

  alias Texttile.Articles
  alias Texttile.Articles.Body
  alias Texttile.Articles.Body.Media
  alias Texttile.Articles.Visibility
  alias Texttile.Images

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
          src={Texttile.Images.url(@brand.logo, :original)}
          alt=""
          class="h-[21px] w-auto max-w-[84px] object-contain"
        />
        <Layouts.mark :if={!@brand.logo} size={21} />
        {@brand.title}
      </a>
      <span :if={@desc != ""} class="site-desc">{@desc}</span>
      <nav class="site-nav" aria-label={gettext("Site")}>
        <a :if={@home_page} id="menu-home" href={~p"/"} aria-current={@active == :home && "page"}>
          {gettext("Home")}
        </a>
        <a id="menu-texts" href={~p"/blog"} aria-current={@active == :texts && "page"}>
          {gettext("Blog")}
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
  The foot of every page: the site name, the way to pass the page on,
  and the door to the admin area. It is not the text either, so it
  keeps the ground of the band over it and the two read as one block; a
  hairline is all that stands between them.

  Share hands the page to the sheet the browser itself opens, on a
  phone and on a Mac. Nothing is loaded for it and no other site hears
  of it. A browser without a sheet has nothing to offer, so there the
  word never appears: it arrives hidden, and `public.js` uncovers it
  where `navigator.share` exists.
  """
  attr :current_scope, :any, default: nil

  def site_foot(assigns) do
    ~H"""
    <footer class="foot-band">
      <div class="wrap f-foot flex flex-wrap items-baseline gap-x-4 gap-y-1.5 pt-4">
        <a href={~p"/"} class="font-semibold text-ink">{site_title()}</a>
        <span class="sp"></span>
        <a :if={Texttile.Feed.public?()} id="foot-feed" href={~p"/feed.xml"}>RSS</a>
        <button type="button" id="foot-share" hidden>{gettext("Share")}</button>
        <a :if={@current_scope} id="foot-admin" href={~p"/admin"}>{gettext("Sign in")}</a>
        <a :if={!@current_scope} id="foot-signin" href={~p"/login"}>{gettext("Sign in")}</a>
      </div>
    </footer>
    """
  end

  @doc """
  The band that ends every reader page: About on the left, Subscribe on
  the right, both in small type on a ground of their own.

  It is the second zone of round 3. Everything over it belongs to the
  text - the neighbours, the comments, the form - and everything on it
  belongs to the blog. The change of ground says that before a word of
  it is read, so neither part needs a heading of the size the text
  uses, and the page ends instead of running out.

  The subscribe form wears the comment form's invisible spam filters: a
  stamp of the moment it was drawn, and a honeypot no person ever sees.
  """
  attr :about_html, :any, default: nil

  def site_band(assigns) do
    assigns =
      assign(
        assigns,
        :newsletter_token,
        Phoenix.Token.sign(TexttileWeb.Endpoint, "newsletter form", System.system_time(:second))
      )

    ~H"""
    <section class="foot-band" id="foot-band" aria-label={gettext("About this blog")}>
      <div class="wrap cols">
        <div :if={@about_html} id="about" aria-label={gettext("About")}>
          <p class="f-eyebrow">{gettext("About")}</p>
          <div class="about-md">{Phoenix.HTML.raw(@about_html)}</div>
        </div>
        <div id="subscribe" aria-label={gettext("Subscribe")}>
          <p class="f-eyebrow">{gettext("Subscribe")}</p>
          <p>
            {gettext(
              "You get an email when a new entry goes out, nothing else. Unsubscribe is one click, no questions."
            )}
          </p>
          <form
            id="newsletter-form"
            action={~p"/newsletter"}
            method="post"
            class="flex items-stretch gap-3 mt-4 max-w-[420px]"
          >
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="t" value={@newsletter_token} />
            <input
              type="text"
              name="url"
              id="nl-hp"
              class="sr"
              tabindex="-1"
              aria-hidden="true"
              autocomplete="off"
            />
            <input
              type="email"
              name="email"
              class="min-w-0 flex-1"
              placeholder="you@example.org"
              aria-label={gettext("Email for new entries")}
              required
            />
            <button class="btn solid flex-none">{gettext("Subscribe")}</button>
          </form>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  The card of the admin area's Texts grid, drawn for a reader. `comments`
  is how many comments stand under the text; the line under the title
  carries it beside the date, so a reader sees where the talking is
  before they open anything.
  """
  attr :article, :any, required: true
  attr :preview, :any, default: nil
  attr :comments, :any, default: nil

  def card(assigns) do
    ~H"""
    <div class="card-wrap">
      <a class="card" id={"text-#{@article.id}"} href={Articles.public_path(@article)}>
        <%!-- every card wears a square, so the grid keeps its rows: the
             picture when there is one, the quiet mark when there is none --%>
        <span :if={@preview} class="cimg">
          <img src={Images.url(@preview, :card)} alt="" loading="lazy" />
        </span>
        <span :if={!@preview} class="cimg blank" aria-hidden="true">
          <Layouts.mark size={34} />
        </span>
        <span class="ct">{Articles.display_title(@article)}</span>
      </a>
      <p class="cm num">
        {format_date(@article.publish_date)}<span :if={Articles.author_name(@article)} class="by">
          · {Articles.author_name(@article)}
        </span>
        <span :if={comment_count(@comments)}>
          ·
          <a
            href={Articles.public_path(@article) <> "#comments"}
            class="clink"
          >
            {comment_count(@comments)}
          </a>
        </span>
      </p>
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

  A video reference becomes a player that fetches nothing until the
  reader presses play: the poster is a picture, the film waits. While
  ffmpeg is still converting, the file stands there as a plain link,
  so the text loses nothing in the meantime.
  """
  def body_html(article) do
    article.body
    |> Body.to_html(&draw_media/1)
    |> Phoenix.HTML.raw()
  end

  # A picture stands in a link to the original, and the script turns
  # that link into the lightbox.
  defp draw_media(%Media{video?: false} = media) do
    ~s(<a class="bodypic" href="#{Images.url(media.path, :original)}" data-full="#{Images.url(media.path, :max)}">) <>
      Media.picture(media, Images.url(media.path, :reading)) <>
      ~s(</a>)
  end

  # While ffmpeg is still converting, the file stands there as a plain
  # link, so the text loses nothing in the meantime.
  defp draw_media(%Media{playback: nil} = media) do
    ~s(<a class="videofile" href="#{Images.url(media.path, :original)}">#{media.label}</a>)
  end

  defp draw_media(%Media{playback: play}) do
    ~s(<video class="bodyvid" controls playsinline preload="none") <>
      ~s( poster="#{Images.url(play.poster, :reading)}") <>
      size_attributes(play) <>
      ~s( src="#{Images.url(play.mp4, :original)}"></video>)
  end

  # The size the browser keeps free before the poster arrives, so the
  # words below do not jump when it does.
  defp size_attributes(%{width: width, height: height})
       when is_integer(width) and is_integer(height) do
    ~s( width="#{width}" height="#{height}")
  end

  defp size_attributes(_play), do: ""

  @doc """
  Whether a text shows a picture at all: a gallery tile, or one in the
  words. The lightbox shell is only drawn where something can open it.
  A video plays where it stands and needs no lightbox of its own.
  """
  def pictures?(article, gallery) do
    gallery != [] or
      Enum.any?(Body.refs(article.body), fn ref ->
        ref.kind == :done and String.starts_with?(to_string(ref.url), "/uploads/") and
          not Texttile.Videos.video?(ref.url)
      end)
  end

  @doc """
  How wide the pictures under a text stand.

  Three or fewer are not a gallery. They belong to the text, so they
  keep the reading column: one fills it, two halve it, three third it.
  The wide grid, which leaves the column on both sides, begins at four
  - that is where a block of tiles reads as a set of its own.
  """
  def gallery_wrap(gallery) when length(gallery) < 4, do: "wrap narrow"
  def gallery_wrap(_gallery), do: "wrap"

  @doc "The shape of the tile grid, see `gallery_wrap/1`."
  def gallery_shape(gallery) when length(gallery) < 4, do: "gal-#{length(gallery)}"
  def gallery_shape(_gallery), do: nil

  @doc "Which use a tile fetches its picture at, see `gallery_wrap/1`."
  def gallery_size([_one]), do: :reading
  def gallery_size(_gallery), do: :card

  @doc "A date the way the example blog writes one: 2 July 2026."
  defdelegate format_date(date), to: Texttile.I18n

  @doc "The lead line of a card, see `Texttile.Articles.lead/1`."
  defdelegate lead(article), to: Articles

  @doc "The heading of the comments block: the count while there is one."
  def comment_heading(0), do: gettext("Comments")
  def comment_heading(n), do: ngettext("1 comment", "%{count} comments", n)

  @doc """
  What a card says about the talking under a text, or nil while nobody
  has said anything: a text without comments carries no zero.
  """
  def comment_count(nil), do: nil
  def comment_count(0), do: nil
  def comment_count(n), do: ngettext("1 comment", "%{count} comments", n)

  @doc """
  The day a comment arrived, the way the example blog writes it: bare
  within the year, with the year once it is another one.
  """
  def comment_when(%DateTime{} = at) do
    date = DateTime.to_date(at)

    if date.year == Date.utc_today().year do
      Texttile.I18n.format_day_and_month(date)
    else
      format_date(date)
    end
  end

  @doc """
  Where the name over a comment leads, or `nil` when it leads nowhere:
  the website its author gave, and this blog itself when one of its own
  wrote the comment signed in. Nothing of that is stored on the
  comment, so the link follows the site wherever it moves.
  """
  def comment_website(%{website: website}) when is_binary(website), do: website
  def comment_website(%{user_id: user_id}) when not is_nil(user_id), do: ~p"/"
  def comment_website(_comment), do: nil

  defdelegate site_title, to: Texttile.Settings
end
