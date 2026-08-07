defmodule TexttileWeb.SiteController do
  @moduledoc """
  The public site: the front door, the text list with its search, the
  texts and pages, the tag archives, and the password gate. Plain
  pages on purpose - readers get HTML, a stylesheet and a few lines of
  script, nothing more.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Gallery
  alias Texttile.Settings
  alias TexttileWeb.SiteGate

  plug :load_chrome when action in [:front, :texts, :tag, :article, :page]

  @doc """
  The front door: the latest texts, or the one fixed page. The About
  block from Settings sits at its foot either way.
  """
  def front(conn, params) do
    conn = assign(conn, :about_html, about_html())

    case conn.assigns.home_page do
      nil -> render_list(conn, params)
      page -> render_text(conn, page)
    end
  end

  @doc "The text list at /texts, the home of the list when a page is the front."
  def texts(conn, params), do: render_list(conn, params)

  @doc """
  One published post, under the day it went live. The date is part of
  the address: another day is another address, and it holds no text.
  """
  def article(conn, %{"year" => year, "month" => month, "day" => day, "slug" => slug}) do
    with {:ok, date} <- Date.from_iso8601("#{year}-#{month}-#{day}"),
         article when not is_nil(article) <- Articles.get_published_post(date, slug) do
      show(conn, article)
    else
      _ -> not_found(conn)
    end
  end

  @doc "One published page, at its short address."
  def page(conn, %{"slug" => slug}) do
    case Articles.get_published_page(slug) do
      nil -> not_found(conn)
      article -> show(conn, article)
    end
  end

  defp show(conn, article) do
    if article.protected and not conn.assigns.site_unlocked do
      redirect(conn, to: ~p"/unlock?to=#{conn.request_path}")
    else
      render_text(conn, article)
    end
  end

  @doc """
  A tag archive: every published text that carries the tag, and the
  other tags beside it, so an archive is also the way into the next one.
  """
  def tag(conn, %{"tag" => raw}) do
    tag = raw |> String.downcase() |> String.trim()
    posts = Articles.list_published(include_protected: conn.assigns.site_unlocked)
    articles = Enum.filter(posts, &(tag in Articles.tag_list(&1)))

    if articles == [] do
      not_found(conn)
    else
      # every tag of the blog, in the order it first appears, with a
      # count each
      tags =
        posts
        |> Enum.flat_map(&Articles.tag_list/1)
        |> Enum.reduce([], fn t, acc -> if t in acc, do: acc, else: [t | acc] end)
        |> Enum.reverse()
        |> Enum.map(fn t ->
          {t, Enum.count(posts, &(t in Articles.tag_list(&1)))}
        end)

      conn
      |> assign(:page_title, "##{tag}")
      |> assign(:active, :texts)
      |> render(:tag,
        tag: tag,
        tags: tags,
        articles: articles,
        previews: Gallery.previews(articles)
      )
    end
  end

  ## The gate

  @doc "The password screen. Chrome-less: a locked reader learns nothing."
  def unlock(conn, params) do
    if SiteGate.unlocked?(conn) do
      redirect(conn, to: SiteGate.safe_return(params["to"]))
    else
      render(conn, :unlock, to: params["to"], error: false)
    end
  end

  @doc "The one password check of the site, plain-text on purpose."
  def enter_password(conn, params) do
    entered = to_string(params["password"])
    stored = Settings.get(:site_password)

    if stored != "" and Plug.Crypto.secure_compare(entered, stored) do
      conn
      |> SiteGate.unlock()
      |> redirect(to: SiteGate.safe_return(params["to"]))
    else
      render(conn, :unlock, to: params["to"], error: true)
    end
  end

  ## The shared chrome and the two page shapes

  # What the header needs on every reader page: the menu pages and the
  # fixed front page. The locked reader's menu holds no protected page.
  defp load_chrome(conn, _opts) do
    pages = Articles.list_pages(include_protected: conn.assigns.site_unlocked)

    home_page =
      with "page:" <> id <- Settings.get(:front_page),
           {id, ""} <- Integer.parse(id) do
        Enum.find(pages, &(&1.id == id))
      else
        _ -> nil
      end

    conn
    |> assign(:home_page, home_page)
    |> assign(:menu_pages, Enum.reject(pages, &(home_page && &1.id == home_page.id)))
  end

  defp render_list(conn, params) do
    q = params |> Map.get("q", "") |> String.trim()
    unlocked = conn.assigns.site_unlocked

    articles = Articles.list_published(search: q, include_protected: unlocked)

    total =
      if q == "" do
        length(articles)
      else
        length(Articles.list_published(include_protected: unlocked))
      end

    conn
    |> assign(:active, :texts)
    |> render(:texts,
      q: q,
      articles: articles,
      previews: Gallery.previews(articles),
      total: total,
      list_path: if(conn.assigns.home_page, do: ~p"/texts", else: ~p"/")
    )
  end

  defp render_text(conn, article) do
    home? = conn.assigns.home_page && conn.assigns.home_page.id == article.id
    gallery = Gallery.list(article.id)

    og_image =
      case Gallery.effective_preview(article, Enum.map(gallery, & &1.path)) do
        nil -> nil
        path -> TexttileWeb.Endpoint.url() <> "/renditions/max/" <> path
      end

    conn
    |> assign(:page_title, if(home?, do: nil, else: Articles.display_title(article)))
    |> assign(:active, if(home?, do: :home, else: article.id))
    |> assign(:og_image, og_image)
    |> render(:article, article: article, gallery: gallery)
  end

  defp about_html do
    case String.trim(Settings.get(:about_markdown)) do
      "" -> nil
      markdown -> Texttile.Markdown.to_html(markdown)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> assign(:page_title, "Not found")
    |> assign(:active, nil)
    |> render(:not_found)
  end
end
