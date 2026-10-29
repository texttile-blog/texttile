defmodule Texttile.Newsletter.Notifier do
  @moduledoc """
  The two mails of the newsletter: the link that confirms an address,
  and the entry that just went live. Both carry the same token - as the
  confirmation link in the first, as the way off the list in the
  second. Each comes twice: as HTML in `TexttileWeb.MailHTML`, and as
  plain text, where every link stands alone on the line right under its
  sentence: no mail program reads a full stop into it, and no blank
  line pushes it away from the words it belongs to.

  The new-text mail may leave from the go-live clock, where no request
  stands behind it, so this module asks the endpoint for the site's
  address instead of taking a URL from a caller.

  Both write in the language of the process that calls them, and ask
  for none of their own. The new-entry mail leaves in a task, and a
  task nobody waits for owns no database connection, so its language is
  handed in where the task is started. See `Texttile.I18n`.
  """

  use Gettext, backend: TexttileWeb.Gettext

  import Swoosh.Email

  alias Texttile.Articles
  alias Texttile.I18n
  alias Texttile.Mailer
  alias Texttile.Newsletter.Subscriber
  alias TexttileWeb.MailHTML

  # The content id the square of a new entry travels under.
  @picture_cid "preview"

  @doc "Mails the link that puts the address on the list."
  def deliver_confirmation(%Subscriber{} = subscriber, url) do
    site = Texttile.Settings.site_title()

    # The subject and the shape are the comment confirmation's, word for
    # word where they can be: this mail confirms an address, like that
    # one, and a mailbox that reads "Get ... by mail" reads an offer.
    subject = gettext("Confirm your email on %{site}", site: site)

    subscriber.email
    |> build(
      site,
      subject,
      gettext(
        """
        This address asked for the new entries of %{site} by mail.

        Open this link, and you are on the list:
        %{url}

        You confirm this address once. If you did not ask for this, ignore this mail. Without the link, the address gets nothing.
        """,
        site: site,
        url: url
      )
    )
    |> html_body(
      MailHTML.render(
        site: site,
        colors: Texttile.Settings.button_colors(),
        subject: subject,
        heading: gettext("Confirm your email"),
        lines: [gettext("This address asked for the new entries of %{site} by mail.", site: site)],
        button: {gettext("Join the list"), url},
        small:
          gettext(
            "You confirm this address once. If you did not ask for this, ignore this mail. Without the link, the address gets nothing."
          )
      )
    )
    |> send()
  end

  @doc """
  Mails one subscriber the entry that just went live: its square, the
  title, who wrote it and when, the lead, the address it lives at, and
  the access word while the blog asks for one. The lead is the taste;
  the entry itself is read on the site.

  `entry` is what the caller read where it owns the database: `:site`,
  `:password`, `:colors`, `:author`, the counts `:pictures` and
  `:videos`, and `:picture`, the bytes of the square or nil.
  """
  def deliver_new_text(%Subscriber{} = subscriber, article, entry) do
    %{site: site, password: password} = entry
    title = Articles.display_title(article)
    url = TexttileWeb.Endpoint.url() <> Articles.public_path(article)

    unsubscribe_url =
      TexttileWeb.Endpoint.url() <> "/newsletter/unsubscribe/#{subscriber.token}"

    # The sender is the site already, so the subject is the title alone.
    subscriber.email
    |> build(
      site,
      title,
      gettext(
        """
        "%{title}" is now on %{site}:
        %{url}
        %{password}
        You get this mail because this address is on the %{site} list. To leave the list, open this link:
        %{unsubscribe}
        """,
        title: title,
        site: site,
        url: url,
        password: password_block(password),
        unsubscribe: unsubscribe_url
      )
    )
    |> html_body(
      MailHTML.render(
        site: site,
        colors: entry.colors,
        subject: title,
        picture: entry.picture && @picture_cid,
        heading: title,
        meta: byline(article, entry),
        lines: Enum.reject([Articles.lead(article)], &(&1 == "")),
        button: {gettext("Read on"), url},
        below: if(password, do: [gettext("Password: %{password}", password: password)], else: []),
        foot:
          {gettext("You get this mail because this address is on the %{site} list.", site: site),
           gettext("Unsubscribe"), unsubscribe_url}
      )
    )
    |> picture(entry.picture)
    # The way off the list, once more where the mail program itself
    # reads it: a mailbox that finds no List-Unsubscribe on mail that
    # goes to a list files it as the kind of mail nobody asked for.
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> send()
  end

  # Who, when, and how much there is to look at: "Klaus · 29 October
  # 2026 · 14 pictures". A part nobody can say is left out.
  defp byline(article, entry) do
    [
      entry.author,
      I18n.format_date(article.publish_date),
      entry.pictures > 0 && ngettext("1 picture", "%{count} pictures", entry.pictures),
      entry.videos > 0 && ngettext("1 video", "%{count} videos", entry.videos)
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" · ")
  end

  # The square travels inside the mail, so it shows behind the blog
  # password too, and opening the mail asks this server for nothing.
  defp picture(email, nil), do: email

  defp picture(email, jpeg) do
    attachment(
      email,
      Swoosh.Attachment.new({:data, jpeg},
        filename: "#{@picture_cid}.jpg",
        content_type: "image/jpeg",
        type: :inline,
        cid: @picture_cid
      )
    )
  end

  # The access word stands right under the link, before the blank line.
  defp password_block(nil), do: ""

  defp password_block(password) do
    gettext("Password: %{password}", password: password) <> "\n"
  end

  # The reader knows the site by its title, not by the product it runs
  # on, so the title is the sender name.
  defp build(to, site, subject, body) do
    new()
    |> to(to)
    |> from({site, Application.fetch_env!(:texttile, :mail_from)})
    |> subject(subject)
    |> text_body(body)
  end

  defp send(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
