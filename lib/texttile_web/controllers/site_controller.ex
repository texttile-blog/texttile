defmodule TexttileWeb.SiteController do
  @moduledoc """
  The public site: the front door, the text list with its search, the
  texts and pages, the tag archives, and the password gate. Plain
  pages on purpose - readers get HTML, a stylesheet and a few lines of
  script, nothing more.
  """
  use TexttileWeb, :controller

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Listing
  alias Texttile.Articles.Reading
  alias Texttile.Articles.Visibility
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
              :blog,
              :tag,
              :article,
              :page,
              :preview,
              :post_comment,
              :confirm_comment,
              :confirm_subscriber
            ]

  # The pages a reader reads report themselves to the view counter.
  # The gate, the newsletter pages and the preview do not: one is not
  # a page of the blog, and the other two are read by nobody a count
  # is about.
  plug :countable when action in [:front, :blog, :tag, :article, :page]

  @doc """
  The front door: the one fixed page, or the way to the list.

  The list has one address of its own, `/blog`, and keeps it whether or
  not a page stands at the front. So `/` never draws the list; it sends
  the reader on, and what they bookmark from there is the address that
  still answers after somebody makes a page the front door.
  """
  def front(conn, params) do
    case conn.assigns.home_page do
      nil -> redirect(conn, to: blog_path(params))
      page -> render_text(conn, page)
    end
  end

  @doc "The list of texts, at /blog."
  def blog(conn, params), do: render_list(conn, params)

  # The search and the page number travel along, so an old link to the
  # front door with a query on it lands on the same list it named.
  defp blog_path(params) do
    pairs =
      for key <- ["q", "y", "m", "page"],
          value = text_value(params[key]),
          value != "",
          do: {key, value}

    case pairs do
      [] -> ~p"/blog"
      pairs -> ~p"/blog" <> "?" <> URI.encode_query(pairs)
    end
  end

  @doc """
  One published post, under the day it went live. The date is part of
  the address: another day is another address, and it holds no text.
  """
  def article(conn, %{"year" => year, "month" => month, "day" => day, "slug" => slug}) do
    with {:ok, date} <- Date.from_iso8601("#{year}-#{month}-#{day}"),
         article when not is_nil(article) <- Reading.post(date, slug, audience(conn)) do
      render_text(conn, article)
    else
      _ -> not_found(conn)
    end
  end

  @doc "One published page, at its short address."
  def page(conn, %{"slug" => slug}) do
    case Reading.page(slug, audience(conn)) do
      nil -> not_found(conn)
      article -> render_text(conn, article)
    end
  end

  @doc """
  An entry on the reader's side while it has no address of its own.

  A draft carries no slug until it goes live, so there is nothing to put
  in an address for it. The editor still owes the writer a way to look
  at the page, and it has to be this page and not a second design of it,
  so the way in is by id. Admins only, like every other way to read an
  entry that is not live.
  """
  def preview(conn, %{"id" => id}) do
    with user when not is_nil(user) <- signed_in_user(conn),
         {id, ""} <- Integer.parse(to_string(id)),
         %Article{} = article <- Articles.get_article(id) do
      render_text(conn, article)
    else
      _ -> not_found(conn)
    end
  end

  # Who this request reads as. `Reading` owns the whole answer to what
  # that audience gets; the controller only names it.
  defp audience(conn), do: Reading.audience(signed_in_user(conn))

  @doc """
  A tag archive: every published text that carries the tag, and the
  other tags beside it, so an archive is also the way into the next one.
  """
  def tag(conn, %{"tag" => raw}) do
    tag = raw |> String.downcase() |> String.trim()
    posts = Articles.list_published() |> Reading.text(audience(conn))
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
        previews: Gallery.previews(articles),
        comment_counts: Comments.reader_count_map()
      )
    end
  end

  ## Comments

  @doc """
  A reader's comment arrives. The invisible filters answer first: a
  filled honeypot, a form younger than a person's typing or a caller
  over the rate limit is dropped without a trace - the sender is told
  that it worked, and nothing is stored.

  Somebody signed in passes all of them. They came through the sign-in,
  so they are no stranger, and their name and their address come from
  the account instead of from the form: the two fields stand there
  filled and disabled, and a browser sends nothing at all for a
  disabled field.
  """
  def post_comment(conn, %{"article_id" => id} = params) do
    article = fetch_commentable(id)
    author = signed_in_user(conn)

    cond do
      is_nil(article) ->
        not_found(conn)

      is_nil(author) and spam?(article, params) ->
        conn |> comment_sent(nil) |> redirect(to: comments_anchor(article))

      true ->
        store_comment(conn, article, params, author)
    end
  end

  defp signed_in_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: %{} = user} -> user
      _ -> nil
    end
  end

  defp store_comment(conn, article, params, author) do
    attrs = comment_attrs(params, author)
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
        # the box travels back too. Without it a reader who ticked it
        # and mistyped one field would send the corrected comment with
        # the box empty, and the address they had asked to keep would
        # be dropped by the correction.
        |> assign(:comment_remember, remember?(params))
        |> assign(:comment_token, to_string(params["t"]))
        |> render_text(article)

      # The limit is spent on storable comments only, so a reader who
      # corrects a form mistake never loses a slot to the mistake. It is
      # a limit on strangers: an account is not one.
      is_nil(author) and not RateLimiter.allow?(client_ip(conn)) ->
        conn |> comment_sent(nil) |> redirect(to: comments_anchor(article))

      true ->
        opts = [confirm_url: &url(~p"/comments/confirm/#{&1}"), user: author]

        case Comments.post(article, attrs, opts) do
          {:ok, comment} ->
            conn
            |> remember_writer(params, attrs, author)
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
      {:ok, %Article{} = article} ->
        if Visibility.live?(article) do
          conn
          |> put_flash(:comment_note, gettext("Confirmed. Your comment is under the entry now."))
          |> redirect(to: comments_anchor(article))
        else
          redirect(conn, to: ~p"/")
        end

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

  # What goes into the comment. The words are always the writer's; the
  # name and the address come from the account while somebody is signed
  # in, so nothing a form could carry can put another name on them.
  defp comment_attrs(params, nil) do
    params |> Map.take(["name", "email", "body", "website"]) |> Map.new(&text_field/1)
  end

  defp comment_attrs(params, user) do
    %{
      "name" => Accounts.display_name(user),
      "email" => to_string(user.email),
      "body" => text_value(params["body"])
    }
  end

  defp spam?(article, params) do
    text_value(params["url"]) != "" or not human_timing?(article, params["t"])
  end

  ## The reader the browser remembers

  # The box under the comment form. It is not ticked to begin with:
  # this cookie is a convenience, nobody needs it to read or to write,
  # and a box that is ticked for you is no answer.
  #
  # The cookie is encrypted, not merely signed. A signed cookie is
  # readable by anybody who reaches the cookie jar, and what stands in
  # this one is the address the form itself promises never to publish.
  # Nothing in the browser ever reads it, so nothing is lost by
  # closing it.
  @writer_cookie "_texttile_writer"
  @writer_months 180 * 24 * 60 * 60

  defp remember?(params), do: text_value(params["remember"]) == "true"

  # Somebody signed in has an account to answer for the two fields, so
  # there is nothing to remember and no box to tick.
  defp remember_writer(conn, _params, _attrs, user) when not is_nil(user), do: conn

  defp remember_writer(conn, params, attrs, _nobody) do
    if remember?(params) do
      put_resp_cookie(conn, @writer_cookie, Map.take(attrs, ["name", "email", "website"]),
        encrypt: true,
        max_age: @writer_months,
        same_site: "Lax",
        http_only: true,
        secure: conn.scheme == :https
      )
    else
      # Only a browser that carries one is handed a Set-Cookie. A
      # reader who never asked gets no header about a cookie they do
      # not have.
      if remembered_writer(conn) == %{} do
        conn
      else
        delete_resp_cookie(conn, @writer_cookie, same_site: "Lax", http_only: true)
      end
    end
  end

  @doc """
  What this browser last wrote a comment under, when the reader asked
  for it to be kept. Only the three fields, and only strings.
  """
  def remembered_writer(conn) do
    conn = fetch_cookies(conn, encrypted: [@writer_cookie])

    case conn.cookies[@writer_cookie] do
      %{} = writer -> Map.new(~w(name email website), &{&1, text_value(writer[&1])})
      _ -> %{}
    end
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

  defp client_ip(conn), do: TexttileWeb.ClientIP.of(conn)

  defp comment_sent(conn, comment) do
    waiting? =
      case comment do
        nil -> Settings.get(:comments_require_confirmation)
        comment -> not Comments.shown_to_readers?(comment)
      end

    note =
      if waiting? do
        gettext("Sent. Follow the link in your mail and your comment appears under the entry.")
      else
        gettext("Sent. Your comment is under the entry now.")
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
    |> assign(:page_title, gettext("Newsletter"))
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
    text_value(params["url"]) != "" or not newsletter_timing?(params["t"])
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
    pages = Articles.list_pages() |> Reading.text(audience(conn))

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

    # The published text for a reader, the working copy for whoever is
    # signed in, so a title being rewritten reads the same on the list
    # as it does in the editor. See `render_text/2`.
    found = Articles.list_published(search: q) |> Reading.text(audience(conn))

    total =
      if q == "" do
        length(found)
      else
        length(Articles.list_published())
      end

    # The field searches every entry of every year; the archive narrows
    # what the field found to one year, and then to one month of it.
    list = Listing.assemble(found, year: params["y"], month: params["m"], page: params["page"])
    list_path = ~p"/blog"

    conn
    |> assign(:active, :texts)
    |> render(:texts,
      q: q,
      articles: list.entries,
      previews: Gallery.previews(list.entries),
      comment_counts: Comments.reader_count_map(),
      found: list.shown,
      total: total,
      across_years: list.across_years,
      year: list.year,
      month: list.month,
      years: list.years,
      months: list.months,
      page: list.page,
      pages: list.pages,
      page_path: &list_link(list_path, q, list.year, list.month, &1),
      period_path: &list_link(list_path, q, &1, &2, 1),
      list_path: list_path
    )
  end

  # One address for the list in any state it can stand in, so a year, a
  # month and a page are all things a reader can copy, bookmark or open
  # in a tab of their own.
  defp list_link(list_path, q, year, month, page) do
    query =
      [
        q: q,
        y: year,
        m: year && month,
        page: if(page == 1, do: nil, else: page)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, "", false] end)

    case query do
      [] -> list_path
      pairs -> list_path <> "?" <> URI.encode_query(pairs)
    end
  end

  # Whether this page reports itself to the view counter. An admin's
  # own visit is not a reader's, so nothing is counted while somebody
  # is signed in - and with them go the drafts and the previews, which
  # nobody else can reach anyway.
  defp countable(conn, _opts) do
    assign(conn, :count_view, is_nil(signed_in_user(conn)))
  end

  defp render_text(conn, article) do
    # The band above the text says which of the two texts is on the
    # screen; `Reading` chooses the text and owes the band.
    audience = audience(conn)
    pending? = Reading.pending?(article, audience)
    article = Reading.text(article, audience)

    home? = conn.assigns.home_page && conn.assigns.home_page.id == article.id
    gallery = Gallery.list(article.id)

    og_image =
      case Gallery.preview_still(article, Enum.map(gallery, & &1.path)) do
        nil -> nil
        path -> TexttileWeb.Endpoint.url() <> Texttile.Images.url(path, :max)
      end

    # A video tile has nothing to show before ffmpeg is through, so the
    # reader's gallery waits for it instead of holding an empty square.
    gallery = Gallery.tiles(gallery)

    {older, newer} = Articles.neighbours(article)

    conn
    |> assign(:page_title, if(home?, do: nil, else: Articles.display_title(article)))
    |> assign(:active, if(home?, do: :home, else: article.id))
    |> assign(:og_image, og_image)
    |> assign(:count_entry, countable_entry(conn, article))
    |> merge_assigns(comment_assigns(conn, article))
    |> render(:article,
      article: article,
      gallery: gallery,
      older: older,
      newer: newer,
      unpublished_changes: pending?
    )
  end

  # The entry the beacon names, if this page counts at all and the
  # entry is one a reader can read.
  defp countable_entry(conn, %Article{id: id} = article) do
    if Visibility.live?(article) and conn.assigns[:count_view], do: id
  end

  # An entry that is not live takes no comments: the reader who could
  # write one cannot reach the page at all, and the form would post to
  # an address that answers nothing.
  # What the comments block under a text needs, or `comments: nil` when
  # the text does not take any. Readers see every comment the rule
  # shows, and their own waiting ones on top - nobody else's.
  defp comment_assigns(conn, %Article{} = article) do
    if Visibility.open_for_comments?(article) do
      comments_block(conn, article)
    else
      %{comments: nil}
    end
  end

  defp comments_block(conn, %Article{} = article) do
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
      comment_rule: comment_rule(signed_in_user(conn), require?),
      # A form that came back with a mistake keeps what was typed; a
      # fresh one starts from what this browser asked to be kept.
      comment_values: conn.assigns[:comment_values] || remembered_writer(conn),
      comment_remember:
        if is_nil(conn.assigns[:comment_remember]) do
          remembered_writer(conn) != %{}
        else
          conn.assigns[:comment_remember]
        end,
      comment_error: conn.assigns[:comment_error] || false,
      comment_author: comment_author(conn)
    }
  end

  # The line under the form. Signed in, the account answers for the
  # address, so there is no link to follow and nothing to confirm.
  defp comment_rule(nil, true) do
    gettext(
      "Your address is never published. You get one link by mail, and your comment appears under the entry once you follow it."
    )
  end

  defp comment_rule(nil, false) do
    gettext("Your address is never published. Your comment appears under the entry at once.")
  end

  defp comment_rule(_user, _require?) do
    gettext(
      "You are signed in, so your name and your address come from your account. Your address is never published, and your comment appears under the entry at once."
    )
  end

  # The account writing the comment, as the form draws it: the name,
  # the address and the website it will carry, so the three fields can
  # stand there filled and disabled instead of asking for what the site
  # already knows. The website of somebody signed in is this blog: they
  # write from the house, and nothing of it is stored on the comment,
  # so the link follows the site wherever it moves.
  defp comment_author(conn) do
    case signed_in_user(conn) do
      nil ->
        nil

      user ->
        %{
          name: Accounts.display_name(user),
          email: to_string(user.email),
          # the host alone: a scheme and a slash in a field nobody
          # types into are noise, and the link itself is built where
          # the comment is drawn
          website: URI.parse(url(~p"/")).host
        }
    end
  end

  defp about_html do
    case String.trim(Settings.get(:about_markdown)) do
      "" -> nil
      markdown -> Texttile.Markdown.to_html(markdown)
    end
  end

  # Nothing here answers this address - unless an entry used to live at
  # it. A moved entry keeps its old addresses alive, so the link
  # somebody shared last year still arrives.
  defp not_found(conn) do
    case Articles.redirect_target(conn.request_path) do
      nil ->
        conn
        |> put_status(:not_found)
        |> assign(:page_title, gettext("Not found"))
        |> assign(:active, nil)
        # An address that holds nothing is no page of the blog, so it
        # is nothing the counter should hear about.
        |> assign(:count_view, false)
        |> render(:not_found)

      target ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: target)
    end
  end
end
