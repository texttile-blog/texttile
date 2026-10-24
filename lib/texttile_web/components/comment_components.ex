defmodule TexttileWeb.CommentComponents do
  @moduledoc """
  The comment row of the admin area and the one rule it follows, in one
  wording. The Comments overview and the editor's Comments tab both
  draw from here, so the two screens can never drift apart.
  """

  use Phoenix.Component
  use Gettext, backend: TexttileWeb.Gettext

  import TexttileWeb.CoreComponents, only: [icon: 1]

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
  last save did not take.
  """
  attr :comment, :any, required: true
  attr :waiting, :boolean, required: true
  attr :article, :any, default: nil
  attr :editing, :boolean, default: false
  attr :error, :string, default: nil

  def comment_item(assigns) do
    ~H"""
    <div class="cmt" id={"comment-#{@comment.id}"}>
      <div class="cmt-top">
        <span class="font-semibold">{@comment.name}</span>
        <.writer_links comment={@comment} />
        <span :if={@waiting} class="wait">{gettext("not confirmed yet")}</span>
        <span class="cmt-when num">{moment_line(@comment)}</span>
      </div>
      <.link :if={@article} navigate={"/admin/texts/#{@article.id}?tab=comments"} class="cmt-ent link">
        {Texttile.Articles.display_title(@article)}
      </.link>

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

      <%!-- comment-body: the words stand here the way the reader typed
           them, line breaks and all, exactly as under the text. The tag
           hugs the words: a line break of the template would be one
           more empty line at the top. --%>
      <p
        :if={!@editing}
        class="comment-body mt-[8px] font-serif text-[15.5px] leading-[1.55] max-w-[62ch]"
        phx-no-format
      >{@comment.body}</p>
      <%!-- three actions on every row would shout in a list this long,
           so they are quiet like the Restore of a version --%>
      <div :if={!@editing} class="mt-[6px] btn-row -ml-[10px]">
        <button class="btn quiet sm" phx-click="start_edit" phx-value-id={@comment.id}>
          {gettext("Edit")}
        </button>
        <button
          :if={@waiting}
          class="btn quiet sm"
          phx-click="release_comment"
          phx-value-id={@comment.id}
        >
          {gettext("Release")}
        </button>
        <button class="btn quiet sm" phx-click="delete_comment" phx-value-id={@comment.id}>
          {gettext("Delete")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  The ways to reach the writer of a comment, as two quiet icons after
  the name: the mail they left, and the website they gave. Only the
  admin area ever draws this, and the address goes no further than the
  mail client it opens: readers never see it anywhere. The website is
  the writer's own, so the link carries the marks of a link a reader
  put there.

  A comment whose address row is gone, or whose author left none, gets
  no mail icon.
  """
  attr :comment, :any, required: true

  def writer_links(assigns) do
    assigns = assign(assigns, :email, email_of(assigns.comment))

    ~H"""
    <a
      :if={@email}
      class="cmt-ico"
      href={"mailto:#{@email}"}
      title={gettext("Write to %{email}", email: @email)}
      aria-label={gettext("Write to %{email}", email: @email)}
    >
      <.icon name="hero-envelope" class="size-[15px]" />
    </a>
    <a
      :if={@comment.website}
      class="cmt-ico"
      href={@comment.website}
      title={host_of(@comment.website)}
      aria-label={host_of(@comment.website)}
      rel="nofollow noopener ugc"
      target="_blank"
    >
      <.icon name="hero-globe-alt" class="size-[15px]" />
    </a>
    """
  end

  # The moment a comment arrived, and the marks it earned since: let
  # through by an admin, rewritten by one. Commas between them.
  defp moment_line(comment) do
    [
      I18n.format_moment(comment.inserted_at),
      Comments.released?(comment) && gettext("let through"),
      Comments.edited?(comment) && gettext("edited")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
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
  goes for good beside the moment, and the way back.
  """
  attr :comment, :any, required: true

  def trashed_item(assigns) do
    ~H"""
    <div class="cmt" id={"trash-#{@comment.id}"}>
      <div class="cmt-top">
        <span class="font-semibold">{@comment.name}</span>
        <.writer_links comment={@comment} />
        <span class="cmt-when num">
          {I18n.format_moment(@comment.inserted_at)}, {gettext("goes for good on")} {I18n.format_plain_day(
            @comment.delete_after
          )}
        </span>
      </div>
      <.link navigate={"/admin/texts/#{@comment.article.id}?tab=comments"} class="cmt-ent link">
        {Texttile.Articles.display_title(@comment.article)}
      </.link>
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
  nothing waits for an admin. An admin can make one exception at a
  time, and can take a deleted comment back out of the trash.
  """
  def comment_rule(true = _require_confirmation?) do
    gettext(
      "Readers confirm their email first. A comment stays out of the entry until the reader follows the link in the mail. Until then only you see it, marked \"not confirmed yet\", and Release puts that one comment under the entry without waiting. Delete keeps a comment in the trash for %{days} days, silently, and then it is gone. Spam is filtered by honeypot, timing and rate limit checks. No captcha, ever.",
      days: Comments.trash_days()
    )
  end

  def comment_rule(false) do
    gettext(
      "A comment appears under the entry the moment a reader sends it, and nobody confirms anything. Delete keeps a comment in the trash for %{days} days, silently, and then it is gone. Spam is filtered by honeypot, timing and rate limit checks. No captcha, ever.",
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
