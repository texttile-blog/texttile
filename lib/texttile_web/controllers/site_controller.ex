defmodule TexttileWeb.SiteController do
  @moduledoc """
  The public site: the front door, the text list with its search, the
  texts and pages, the tag archives, and the password gate. Plain
  pages on purpose - readers get HTML, a stylesheet and a few lines of
  script, nothing more.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Comments
  alias Texttile.Newsletter
  alias Texttile.RateLimiter
  alias Texttile.Gallery
  alias Texttile.Settings
  alias TexttileWeb.SiteGate

  # confirm_subscriber is here for its 404 branch only; the newsletter
  # pages themselves are chrome-less like the gate.
  plug :load_chrome
       when action in [
              :front,
              :texts,
              :tag,
              :article,
              :page,
              :post_comment,
              :confirm_comment,
              :confirm_subscriber
            ]

  @doc "The front door: the latest texts, or the one fixed page."
  def front(conn, params) do
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
      render_text(conn, article)
    else
      _ -> not_found(conn)
    end
  end

  @doc "One published page, at its short address."
  def page(conn, %{"slug" => slug}) do
    case Articles.get_published_page(slug) do
      nil -> not_found(conn)
      article -> render_text(conn, article)
    end
  end

  @doc """
  A tag archive: every published text that carries the tag, and the
  other tags beside it, so an archive is also the way into the next one.
  """
  def tag(conn, %{"tag" => raw}) do
    tag = raw |> String.downcase() |> String.trim()
    posts = Articles.list_published()
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

  ## Comments

  @doc """
  A reader's comment arrives. The invisible filters answer first: a
  filled honeypot, a form younger than a person's typing or a caller
  over the rate limit is dropped without a trace - the sender is told
  that it worked, and nothing is stored.
  """
  def post_comment(conn, %{"article_id" => id} = params) do
    article = fetch_commentable(id)

    cond do
      is_nil(article) ->
        not_found(conn)

      spam?(article, params) ->
        conn |> comment_sent(nil) |> redirect(to: comments_anchor(article))

      true ->
        store_comment(conn, article, params)
    end
  end

  defp store_comment(conn, article, params) do
    attrs = params |> Map.take(["name", "email", "body"]) |> Map.new(&text_field/1)
    changeset = Comments.Comment.post_changeset(%Comments.Comment{}, attrs)

    cond do
      not changeset.valid? ->
        # The words travel back into the form, with one line that says
        # what is missing. No comment is stored, and the stamp of the
        # first drawing travels with them: a fresh one would make the
        # corrected comment look like a script to the time trap.
        conn
        |> assign(:comment_error, true)
        |> assign(:comment_values, attrs)
        |> assign(:comment_token, to_string(params["t"]))
        |> render_text(article)

      # The limit is spent on storable comments only, so a reader who
      # corrects a form mistake never loses a slot to the mistake.
      not RateLimiter.allow?(client_ip(conn)) ->
        conn |> comment_sent(nil) |> redirect(to: comments_anchor(article))

      true ->
        case Comments.post(article, attrs, confirm_url: &url(~p"/comments/confirm/#{&1}")) do
          {:ok, comment} ->
            conn
            |> put_session(:own_comments, Enum.take([comment.id | own_comment_ids(conn)], 20))
            |> comment_sent(comment)
            |> redirect(to: comments_anchor(article))

          {:error, _} ->
            not_found(conn)
        end
    end
  end

  @doc """
  The mailed link: the address is confirmed and the reader lands where
  their comment now stands for everybody.
  """
  def confirm_comment(conn, %{"token" => token}) do
    case Comments.confirm(token) do
      {:ok, %Article{status: "published"} = article} ->
        conn
        |> put_flash(:comment_note, "Confirmed. Your comment is under the text now.")
        |> redirect(to: comments_anchor(article))

      {:ok, _gone} ->
        redirect(conn, to: ~p"/")

      :error ->
        not_found(conn)
    end
  end

  # Only a published text that allows comments takes one.
  defp fetch_commentable(id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Article{allow_comments: true} = article <- Articles.get_published(id) do
      article
    else
      _ -> nil
    end
  end

  defp spam?(article, params) do
    text_value(params["website"]) != "" or not human_timing?(article, params["t"])
  end

  # A form field is one line of text. A caller who sends a list or a map
  # instead (`body[]=x`) gets it read as nothing, not a 500.
  defp text_field({key, value}), do: {key, text_value(value)}

  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: ""

  # The form carries a signed stamp of the moment it was drawn. Sent
  # back in under a few seconds means a script, not a person typing;
  # no stamp or a foreign stamp means the form was never drawn at all.
  defp human_timing?(article, token) do
    min_age = Application.get_env(:texttile, :comment_min_age, 3)

    case Phoenix.Token.verify(TexttileWeb.Endpoint, "comment form", text_value(token),
           max_age: 7 * 86_400
         ) do
      {:ok, {article_id, signed_at}} ->
        article_id == article.id and System.system_time(:second) - signed_at >= min_age

      _ ->
        false
    end
  end

  # The caller as the rate limiter knows it: the socket address, which
  # no caller can choose. A forwarding header is read only where the
  # deployment names one (CLIENT_IP_HEADER, see the README): behind a
  # proxy the socket address is the proxy's, and without the header
  # every reader would share one bucket. Anywhere else the header is
  # just a line the caller wrote, and trusting it would hand every
  # spammer a fresh bucket per request.
  defp client_ip(conn) do
    header = Application.get_env(:texttile, :client_ip_header)

    with name when is_binary(name) <- header,
         [value | _] <- get_req_header(conn, name),
         first when first != "" <- value |> String.split(",") |> hd() |> String.trim() do
      first
    else
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp comment_sent(conn, comment) do
    waiting? =
      case comment do
        nil -> Settings.get(:comments_require_confirmation)
        comment -> not Comments.shown_to_readers?(comment)
      end

    note =
      if waiting? do
        "Sent. Follow the link in your mail and your comment appears under the text."
      else
        "Sent. Your comment is under the text now."
      end

    put_flash(conn, :comment_note, note)
  end

  defp comments_anchor(article), do: Articles.public_path(article) <> "#comments"

  defp own_comment_ids(conn), do: get_session(conn, :own_comments) || []

  ## Newsletter

  @doc """
  A reader asks for the newsletter through the footer form. The same
  invisible filters as on the comment form answer first, and a dropped
  request is told that it worked - the sender learns nothing. What
  every path lands on is a plain page, not the page the form stood on:
  the form stands everywhere, and the answer matters more than the
  place.
  """
  def join_newsletter(conn, params) do
    email = text_value(params["email"])

    cond do
      newsletter_spam?(params) ->
        newsletter_page(conn, :sent, email)

      not Newsletter.Subscriber.address?(Newsletter.Subscriber.normalize(email)) ->
        # The words travel back into the form. The stamp travels with
        # them, so the corrected address is not a script to the trap.
        newsletter_page(conn, :retry, email, t: to_string(params["t"]))

      # The limit is spent on storable requests only.
      not RateLimiter.allow?(client_ip(conn)) ->
        newsletter_page(conn, :sent, email)

      true ->
        {:ok, _} = Newsletter.join(email, confirm_url: &url(~p"/newsletter/confirm/#{&1}"))
        newsletter_page(conn, :sent, email)
    end
  end

  @doc "The mailed link: the address is on the list from here on."
  def confirm_subscriber(conn, %{"token" => token}) do
    case Newsletter.confirm(token) do
      {:ok, subscriber} -> newsletter_page(conn, :confirmed, subscriber.email)
      :error -> not_found(conn)
    end
  end

  @doc """
  The way off the list, as a question: one page, one button. A mail
  scanner that opens every link must not take anybody off the list, so
  the leaving itself is the POST below. A spent link answers the same
  as the button: to the person leaving, both mean off the list.
  """
  def unsubscribe(conn, %{"token" => token}) do
    case Newsletter.by_token(token) do
      nil -> newsletter_page(conn, :left, nil)
      subscriber -> newsletter_page(conn, :leave, subscriber.email, token: token)
    end
  end

  @doc "The button was pressed: the address goes off the list."
  def do_unsubscribe(conn, %{"token" => token}) do
    :ok = Newsletter.unsubscribe(token)
    newsletter_page(conn, :left, nil)
  end

  defp newsletter_page(conn, state, email, extra \\ []) do
    conn
    |> assign(:page_title, "Newsletter")
    |> render(:newsletter,
      state: state,
      email: email,
      t: Keyword.get(extra, :t),
      token: Keyword.get(extra, :token)
    )
  end

  # The same two invisible filters as on the comment form; the stamp
  # carries no article, only the moment the footer was drawn.
  defp newsletter_spam?(params) do
    text_value(params["website"]) != "" or not newsletter_timing?(params["t"])
  end

  defp newsletter_timing?(token) do
    min_age = Application.get_env(:texttile, :comment_min_age, 3)

    case Phoenix.Token.verify(TexttileWeb.Endpoint, "newsletter form", text_value(token),
           max_age: 7 * 86_400
         ) do
      {:ok, signed_at} -> System.system_time(:second) - signed_at >= min_age
      _ -> false
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
  # fixed front page. The About block from Settings comes along; it
  # stands at the foot of every text and of the list.
  defp load_chrome(conn, _opts) do
    pages = Articles.list_pages()

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
    |> assign(:about_html, about_html())
  end

  defp render_list(conn, params) do
    q = params |> Map.get("q", "") |> String.trim()

    found = Articles.list_published(search: q)

    total =
      if q == "" do
        length(found)
      else
        length(Articles.list_published())
      end

    per_page = Settings.get(:posts_per_page)
    pages = max(div(length(found) - 1, per_page) + 1, 1)
    page = page_number(params["page"], pages)
    articles = Enum.slice(found, (page - 1) * per_page, per_page)
    list_path = if conn.assigns.home_page, do: ~p"/texts", else: ~p"/"

    conn
    |> assign(:active, :texts)
    |> render(:texts,
      q: q,
      articles: articles,
      previews: Gallery.previews(articles),
      found: length(found),
      total: total,
      page: page,
      pages: pages,
      page_path: &page_path(list_path, q, &1),
      list_path: list_path
    )
  end

  # A page number outside the row is no error: a bookmark from a
  # shorter blog, or a ?page= somebody typed, lands on the last page.
  defp page_number(raw, pages) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n > 0 -> min(n, pages)
      _ -> 1
    end
  end

  defp page_path(list_path, q, page) do
    query =
      [q: q, page: if(page == 1, do: nil, else: page)]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    case query do
      [] -> list_path
      pairs -> list_path <> "?" <> URI.encode_query(pairs)
    end
  end

  defp render_text(conn, article) do
    home? = conn.assigns.home_page && conn.assigns.home_page.id == article.id
    gallery = Gallery.list(article.id)

    og_image =
      case Gallery.preview_still(article, Enum.map(gallery, & &1.path)) do
        nil -> nil
        path -> TexttileWeb.Endpoint.url() <> "/renditions/max/" <> path
      end

    # A video tile has nothing to show before ffmpeg is through, so the
    # reader's gallery waits for it instead of holding an empty square.
    gallery = Gallery.tiles(gallery)

    {older, newer} = Articles.neighbours(article)

    conn
    |> assign(:page_title, if(home?, do: nil, else: Articles.display_title(article)))
    |> assign(:active, if(home?, do: :home, else: article.id))
    |> assign(:og_image, og_image)
    |> merge_assigns(comment_assigns(conn, article))
    |> render(:article, article: article, gallery: gallery, older: older, newer: newer)
  end

  # What the comments block under a text needs, or `comments: nil` when
  # the text does not take any. Readers see every comment the rule
  # shows, and their own waiting ones on top - nobody else's.
  defp comment_assigns(conn, %Article{allow_comments: true} = article) do
    require? = Settings.get(:comments_require_confirmation)
    own = own_comment_ids(conn)
    {comments, earlier} = Comments.for_readers(article.id)

    rows =
      Enum.flat_map(comments, fn comment ->
        cond do
          Comments.shown_to_readers?(comment, require?) -> [{:shown, comment}]
          comment.id in own -> [{:own, comment}]
          true -> []
        end
      end)

    %{
      comments: rows,
      comment_count: Enum.count(rows, &match?({:shown, _}, &1)) + earlier,
      comment_earlier: earlier,
      comment_token:
        conn.assigns[:comment_token] ||
          Phoenix.Token.sign(
            TexttileWeb.Endpoint,
            "comment form",
            {article.id, System.system_time(:second)}
          ),
      comment_note: Phoenix.Flash.get(conn.assigns.flash, :comment_note),
      comment_rule:
        if(require?,
          do:
            "Your address is never published. You get one link by mail, and " <>
              "your comment appears under the text once you follow it.",
          else: "Your address is never published. Your comment appears under the text at once."
        ),
      comment_values: conn.assigns[:comment_values] || %{},
      comment_error: conn.assigns[:comment_error] || false
    }
  end

  defp comment_assigns(_conn, _article), do: %{comments: nil}

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
