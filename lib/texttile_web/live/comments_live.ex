defmodule TexttileWeb.CommentsLive do
  @moduledoc """
  The Comments overview: the latest comments across all texts, newest
  first, each with the jump to its text, an Edit, a Release while it
  waits, and a Delete. The trash stands under them while it holds
  anything, and it is the only place that shows a deleted comment. The
  lead line carries the counts; the note at the foot carries the rule.
  Round-13's Comments screen.
  """

  use TexttileWeb, :live_view

  import TexttileWeb.CommentComponents

  alias Texttile.Comments
  alias Texttile.Settings

  @shown 8

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Comments.subscribe()
      Settings.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Comments"))
     |> assign(:dialog, nil)
     |> TexttileWeb.CommentModeration.attach(reload: &load/1)
     |> load()}
  end

  defp load(socket) do
    {trashed, trashed_earlier} = Comments.trashed()

    socket
    |> assign(:recent, Comments.recent(@shown))
    |> assign(:total, Comments.total_count())
    |> assign(:waiting, Comments.waiting_count())
    |> assign(:trashed, trashed)
    |> assign(:trashed_earlier, trashed_earlier)
    |> assign(:require?, Settings.get(:comments_require_confirmation))
  end

  # The six moderation events are answered by CommentModeration; only
  # what is of this screen alone stays here. The trash lives on this
  # screen, so the restore does too.
  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  # A comment another admin restored a moment ago is simply back; the
  # list reloads either way.
  def handle_event("restore_comment", %{"id" => id}, socket) do
    Comments.restore_comment(id)
    {:noreply, load(socket)}
  end

  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_changed, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comments_confirmed, _address_id}, socket), do: {:noreply, load(socket)}
  def handle_info({:comments_imported, _article_id}, socket), do: {:noreply, load(socket)}

  def handle_info({:setting_changed, :comments_require_confirmation, _}, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Comments")}
      active="comments"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <%!-- the heading carries the one piece of news: how many wait for
             a confirmed address, in the words of the mark each of them
             wears. Beside the heading like the count of the Entries
             grid, and gone while nothing waits. --%>
        <div class="flex items-baseline gap-[14px] flex-wrap mb-[18px]">
          <h1 class="page-h">{gettext("Comments")}</h1>
          <span :if={@waiting > 0} class="note num" id="commentsSub">
            {ngettext("1 not confirmed yet", "%{count} not confirmed yet", @waiting)}
          </span>
        </div>
        <div id="commentsList">
          <p :if={@recent == []} class="note">
            {gettext("No comments yet, anywhere. Every comment a reader sends shows up here.")}
          </p>
          <%!-- the address behind a comment is loaded with it, so the
               name can be the way to write back --%>
          <.comment_item
            :for={comment <- @recent}
            comment={comment}
            waiting={Comments.waiting?(comment, @require?)}
            article={comment.article}
            editing={@editing_comment == to_string(comment.id)}
            error={@comment_error}
          />
          <div :if={@total > length(@recent)} class="pt-[4px] text-[12.5px] text-faint">
            {gettext("and %{count} more on their entries.", count: @total - length(@recent))}
          </div>
        </div>
        <p class="note mt-[22px]" id="commentsRule">{comment_rule(@require?)}</p>

        <section :if={@trashed != []} id="commentsTrash">
          <h2 class="set-h">{gettext("Trash")}</h2>
          <p class="note mb-[13px]">
            {trash_line(length(@trashed) + @trashed_earlier)}
          </p>
          <.trashed_item :for={comment <- @trashed} comment={comment} />
          <div :if={@trashed_earlier > 0} class="pt-[4px] text-[12.5px] text-faint">
            {ngettext(
              "and %{count} deleted earlier, closer to the day it goes for good.",
              "and %{count} deleted earlier, closer to the day they go for good.",
              @trashed_earlier
            )}
          </div>
        </section>
      </div>

      <.ask
        :if={@dialog}
        heading={@dialog.title}
        ok={@dialog.ok}
        on_ok={@dialog.event}
        value={@dialog.value}
      >
        <p :for={line <- @dialog.body} class="mt-[9px] first:mt-0">{line}</p>
      </.ask>
    </Layouts.app>
    """
  end

  # The line over the trash: what stands there, and for how much longer.
  defp trash_line(count) do
    ngettext(
      "1 deleted comment waits here. A comment goes for good %{days} days after you deleted it, and until then Restore puts it back where it stood.",
      "%{count} deleted comments wait here. A comment goes for good %{days} days after you deleted it, and until then Restore puts it back where it stood.",
      count,
      days: Comments.trash_days()
    )
  end
end
