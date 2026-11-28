defmodule TexttileWeb.CommentComponents do
  @moduledoc """
  The comment row of the admin area and the one rule it follows, in one
  wording. The Comments overview and the editor's Comments tab both
  draw from here, so the two screens can never drift apart.
  """

  use Phoenix.Component
  use Gettext, backend: TexttileWeb.Gettext

  alias Texttile.Comments
  alias Texttile.I18n

  @doc """
  One comment on an admin screen, as a block on the page: the name with
  the ways to reach its writer, the waiting mark while the reader has
  not confirmed, the moment at the right, the entry under it, then the
  words and what an admin can do with them - Edit, Release while it
  waits, Delete. `article` set draws the entry line, the jump of the
  overview; the editor is on the entry already and leaves it out.
  `editing` puts the words in a field instead, `error` says why the
  last save did not take. `selected` draws the box of the overview,
  true or false; the editor leaves it out and gets no box.
  """
  attr :comment, :any, required: true
  attr :waiting, :boolean, required: true
  attr :article, :any, default: nil
  attr :editing, :boolean, default: false
  attr :error, :string, default: nil
  attr :selected, :any, default: nil

  def comment_item(assigns) do
    ~H"""
    <div class={row_class(@selected)} id={"comment-#{@comment.id}"}>
      <.pick :if={is_boolean(@selected)} comment={@comment} selected={@selected} />
      <div class="cmt-top">
        <span class="cmt-who">
          <span class="rowp">{@comment.name}</span>
          <span :if={@waiting} class="cmt-st wait">
            <i class="cmt-dot-st" aria-hidden="true"></i>{gettext("Unconfirmed")}
          </span>
          <span :if={!@waiting} class="cmt-st ok">{gettext("Approved")}</span>
          <span class="cmt-dot" aria-hidden="true">·</span>
          <span class="cmt-when num" phx-no-format><time
              id={"cmt-at-#{@comment.id}"}
              datetime={DateTime.to_iso8601(@comment.inserted_at)}
              phx-hook="LocalMoment"
            >{I18n.format_short_moment(@comment.inserted_at)}</time>{moment_tail(@comment)}</span>
        </span>
      </div>

      <form
        :if={@editing}
        id={"edit-comment-#{@comment.id}"}
        phx-submit="save_comment"
        class="mt-[7px] max-w-[62ch]"
      >
        <input type="hidden" name="comment_id" value={@comment.id} />
        <%!-- the list behind this form reloads on every comment posted
             anywhere on the site; ignored, the field keeps what the
             admin has typed into it so far --%>
        <div id={"edit-body-#{@comment.id}"} phx-update="ignore">
          <textarea
            name="body"
            rows="4"
            maxlength={Comments.body_limit()}
            class="w-full font-serif text-[15.5px] leading-[1.55]"
            aria-label={gettext("The words of the comment")}
            autofocus
          >{@comment.body}</textarea>
        </div>
        <p :if={@error} class="hint text-accent" id={"edit-error-#{@comment.id}"}>{@error}</p>
        <div class="mt-[9px] btn-row">
          <button class="btn sm solid">{gettext("Save")}</button>
          <button type="button" class="btn sm" phx-click="cancel_edit">{gettext("Cancel")}</button>
        </div>
      </form>

      <%!-- comment-body sits immediately under author and status (unbroken reading sequence) --%>
      <p
        :if={!@editing}
        class="comment-body mt-[5px] font-serif text-[16px] leading-[1.56] max-w-[78ch]"
        phx-no-format
      >{String.trim(@comment.body)}</p>

      <%!-- unified provenance line below the body: entry title, with optional website
           on desktop (tucked into row overflow on phones so actions stay close). --%>
      <div class="cmt-sub">
        <span :if={@article} class="cmt-on">{gettext("on")} <.link
          navigate={"/admin/texts/#{@article.id}?tab=comments"}
          class="cmt-ent"
          phx-no-format
        >{Texttile.Articles.display_title(@article)}</.link></span>
        <span :if={@comment.website} class="hidden sm:inline cmt-tail">
          <span class="cmt-web-sep" aria-hidden="true">·</span><.website comment={@comment} />
        </span>
      </div>

      <%!-- Pure action bar: Approve (when waiting), Reply, and overflow --%>
      <div :if={!@editing} class="cmt-acts">
        <button
          :if={@waiting}
          class="btn quiet sm rel flex-none"
          title={gettext("Show the comment now, before its reader confirms")}
          phx-click="release_comment"
          phx-value-id={@comment.id}
        >
          {gettext("Approve")}
        </button>
        <.write_link comment={@comment} />
        <details class="cmt-more" id={"cmt-more-#{@comment.id}"}>
          <summary
            class="btn quiet sm cmt-more-btn"
            aria-label={gettext("More actions for %{name}'s comment", name: @comment.name)}
            title={gettext("More actions")}
          >
            <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
              <circle cx="3.2" cy="8" r="1.25" />
              <circle cx="8" cy="8" r="1.25" />
              <circle cx="12.8" cy="8" r="1.25" />
            </svg>
          </summary>
          <div class="cmt-more-pop">
            <a
              :if={@comment.website}
              class="cmt-more-row sm:hidden"
              href={@comment.website}
              title={@comment.website}
              rel="nofollow noopener ugc"
              target="_blank"
            >
              {host_of(@comment.website)} &nearr;
            </a>
            <button
              type="button"
              class="cmt-more-row"
              phx-click="start_edit"
              phx-value-id={@comment.id}
            >
              {gettext("Edit")}
            </button>
            <button
              type="button"
              class="cmt-more-row danger"
              phx-click="delete_comment"
              phx-value-id={@comment.id}
            >
              {gettext("Delete")}
            </button>
          </div>
        </details>
      </div>
    </div>
    """
  end

  @doc """
  The way to answer the writer of a comment: Reply, a quiet action that
  opens the mail client on the address they left. Only the admin area
  ever draws this, and the address goes no further than that mail
  client: readers never see it anywhere. A comment whose address row
  is gone, or whose author left none, gets no Reply.
  """
  attr :comment, :any, required: true

  def write_link(assigns) do
    assigns = assign(assigns, :email, email_of(assigns.comment))

    ~H"""
    <a
      :if={@email}
      class="btn quiet sm cmt-reply"
      href={"mailto:#{@email}"}
      title={gettext("Write to %{email}", email: @email)}
    >
      {gettext("Reply")}
    </a>
    """
  end

  @doc """
  The website a writer gave, as its host after the moment. It is the
  writer's own, so the link carries the marks of a link a reader put
  there.
  """
  attr :comment, :any, required: true

  def website(assigns) do
    ~H"""
    <a
      :if={@comment.website}
      class="cmt-web"
      href={@comment.website}
      title={@comment.website}
      rel="nofollow noopener ugc"
      target="_blank"
    >
      {host_of(@comment.website)}
    </a>
    """
  end

  defp row_class(selected), do: ["cmt", is_boolean(selected) && "sel", selected == true && "on"]

  # The label is the touch target: a box alone is too small for a thumb.
  attr :comment, :any, required: true
  attr :selected, :boolean, required: true

  defp pick(assigns) do
    ~H"""
    <label class="cmt-pick">
      <input
        type="checkbox"
        checked={@selected}
        phx-click="toggle_comment"
        phx-value-id={@comment.id}
        aria-label={gettext("Select the comment of %{name}", name: @comment.name)}
      />
    </label>
    """
  end

  # The moment a comment arrived, and the marks it earned since: let
  # through by an admin, rewritten by one. Commas between them.
  # What follows the moment of a comment: let through, edited.
  defp moment_tail(comment) do
    if Comments.edited?(comment), do: ", " <> gettext("edited"), else: ""
  end

  # The address to write back to. An imported comment whose author
  # left none carries the placeholder address instead, and a mailto to
  # that one would be a dead letter.
  defp email_of(%{address: %{email: email}}) when is_binary(email) and email != "" do
    if email == Comments.placeholder_address(), do: nil, else: email
  end

  defp email_of(_comment), do: nil

  # The host alone: a whole URL after a name is a wall of text.
  defp host_of(website), do: URI.parse(website).host || website

  @doc """
  One comment in the trash: the same block, dimmed, with the day it
  goes for good beside the moment, and the way back. `selected` draws
  the box, as on `comment_item/1`.
  """
  attr :comment, :any, required: true
  attr :selected, :any, default: nil

  def trashed_item(assigns) do
    ~H"""
    <div class={row_class(@selected)} id={"trash-#{@comment.id}"}>
      <.pick :if={is_boolean(@selected)} comment={@comment} selected={@selected} />
      <div class="cmt-top">
        <span class="rowp">{@comment.name}</span>
      </div>
      <div class="cmt-sub">
        <.link navigate={"/admin/texts/#{@comment.article.id}?tab=comments"} class="cmt-ent">
          {Texttile.Articles.display_title(@comment.article)}
        </.link>
        <span class="cmt-when num">
          {I18n.format_short_moment(@comment.inserted_at)}, {gettext("goes for good on")} {I18n.format_short_date(
            DateTime.to_date(@comment.delete_after)
          )}
        </span>
      </div>
      <p
        class="comment-body mt-[8px] font-serif text-[15.5px] leading-[1.55] max-w-[62ch] text-dim"
        phx-no-format
      >{@comment.body}</p>
      <div class="mt-[6px] -ml-[10px]">
        <button class="btn quiet sm" phx-click="restore_comment" phx-value-id={@comment.id}>
          {gettext("Restore")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  The one rule, in the one wording. Nothing here is an approval queue:
  nothing waits for an admin. An admin can make an exception, and can
  take a deleted comment back out of the trash.
  """
  def comment_rule(true = _require_confirmation?) do
    gettext(
      "Readers confirm their email before a comment goes live. Approve publishes right away; unconfirmed comments expire after %{waiting} days.",
      waiting: Comments.waiting_days()
    )
  end

  def comment_rule(false) do
    gettext(
      "Comments appear the moment a reader sends them. Deleted comments stay in the trash for %{days} days.",
      days: Comments.trash_days()
    )
  end

  @doc """
  The question an admin answers before a comment goes, in one wording
  for both screens: what it does, and what it does not do. The shape is
  the one `<.ask>` reads, so it travels there as it stands.
  """
  def delete_dialog(comment) do
    %{
      title: gettext("Delete the comment of %{name}?", name: comment.name),
      body: [
        gettext("It removes the comment from the entry at once, and the reader is not told."),
        gettext(
          "The trash on the Comments screen keeps it for %{days} days. Restore puts it back where it stood; after that it is gone for good.",
          days: Comments.trash_days()
        )
      ],
      ok: gettext("Delete the comment"),
      event: "confirm_delete_comment",
      value: comment.id
    }
  end

  @doc """
  Why the last save did not take, in the words of the changeset that
  refused it: nothing there, or more than a comment holds.
  """
  def edit_error(%Ecto.Changeset{} = changeset) do
    case Keyword.get(changeset.errors, :body) do
      {_message, opts} ->
        if Keyword.get(opts, :validation) == :length do
          gettext("A comment holds %{count} characters at most. Nothing was saved.",
            count: Keyword.get(opts, :count)
          )
        else
          gettext("A comment needs some words. Nothing was saved.")
        end

      nil ->
        gettext("Those words were not saved.")
    end
  end
end
