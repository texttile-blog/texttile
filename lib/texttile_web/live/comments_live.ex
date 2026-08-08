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
     |> assign(:page_title, "Comments")
     |> assign(:editing, nil)
     |> assign(:edit_error, nil)
     |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:recent, Comments.recent(@shown))
    |> assign(:total, Comments.total_count())
    |> assign(:waiting, Comments.waiting_count())
    |> assign(:trashed, Comments.trashed())
    |> assign(:require?, Settings.get(:comments_require_confirmation))
  end

  # A comment the other desk deleted a moment ago is simply gone; the
  # list reloads either way. The same for the restore and the release.
  def handle_event("delete_comment", %{"id" => id}, socket) do
    Comments.delete_comment(id)
    {:noreply, socket |> close_edit() |> load()}
  end

  def handle_event("restore_comment", %{"id" => id}, socket) do
    Comments.restore_comment(id)
    {:noreply, load(socket)}
  end

  def handle_event("release_comment", %{"id" => id}, socket) do
    Comments.release_comment(id)
    {:noreply, load(socket)}
  end

  # One comment stands open at a time; opening another closes the first
  # and drops what it said about the last save.
  def handle_event("start_edit", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:editing, to_string(id)) |> assign(:edit_error, nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, close_edit(socket)}
  end

  def handle_event("save_comment", %{"comment_id" => id, "body" => body}, socket) do
    case Comments.edit_comment(id, body) do
      {:ok, _comment} -> {:noreply, socket |> close_edit() |> load()}
      {:error, :gone} -> {:noreply, socket |> close_edit() |> load()}
      {:error, _changeset} -> {:noreply, assign(socket, :edit_error, empty_words())}
    end
  end

  defp close_edit(socket), do: socket |> assign(:editing, nil) |> assign(:edit_error, nil)

  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_changed, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comments_confirmed, _address_id}, socket), do: {:noreply, load(socket)}

  def handle_info({:setting_changed, :comments_require_confirmation, _}, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Comments"
      active="comments"
      others={@others}
    >
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">Comments</h1>
        <p class="lead" id="commentsSub">{sub_line(@total, @waiting, @require?)}</p>
        <div id="commentsList">
          <p :if={@recent == []} class="note">
            No comments yet, anywhere. Every comment a reader sends shows up here.
          </p>
          <.comment_item
            :for={comment <- @recent}
            comment={comment}
            waiting={waiting?(comment, @require?)}
            article={comment.article}
            editing={@editing == to_string(comment.id)}
            error={@edit_error}
          />
          <div
            :if={@total > length(@recent)}
            class="py-[11px] text-[12.5px] text-faint border-t border-hair"
          >
            and {@total - length(@recent)} more on their texts.
          </div>
        </div>
        <p class="note mt-[22px] max-w-[62ch]" id="commentsRule">{comment_rule(@require?)}</p>

        <section :if={@trashed != []} id="commentsTrash">
          <h2 class="set-h">Trash</h2>
          <p class="note mb-[13px] max-w-[62ch]">{trash_line(length(@trashed))}</p>
          <.trashed_item :for={comment <- @trashed} comment={comment} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  # A comment waits while the setting asks for a confirmation, its
  # reader has not given one, and the desk has not let it through.
  defp waiting?(comment, require?) do
    require? and is_nil(comment.address.confirmed_at) and not Comments.released?(comment)
  end

  # The line over the trash: what stands there, and for how much longer.
  defp trash_line(count) do
    "#{count} deleted #{plural(count, "comment waits", "comments wait")} here. " <>
      "A comment goes for good #{Comments.trash_days()} days after you deleted it, " <>
      "and until then Restore puts it back where it stood."
  end

  # The lead line: how many, and where the waiting ones stand.
  defp sub_line(0, _waiting, _require?), do: "The latest comments across all texts, newest first."

  defp sub_line(total, 0, require?) do
    "#{total} #{plural(total, "comment", "comments")} across all texts, newest first." <>
      if require? do
        " Every one of them is confirmed, so readers see them all."
      else
        " Readers see every one of them."
      end
  end

  defp sub_line(total, waiting, _require?) do
    "#{total} #{plural(total, "comment", "comments")} across all texts, newest first. " <>
      "#{waiting} #{plural(waiting, "comment waits", "comments wait")} for the reader " <>
      "to confirm the email address, so readers do not see " <>
      plural(waiting, "it", "them") <> " yet."
  end
end
