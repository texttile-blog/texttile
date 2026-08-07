defmodule TexttileWeb.CommentsLive do
  @moduledoc """
  The Comments overview: the latest comments across all texts, newest
  first, each with the jump to its text and a Delete. The lead line
  carries the counts; the note at the foot carries the rule. Round-13's
  Comments screen.
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
     |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:recent, Comments.recent(@shown))
    |> assign(:total, Comments.total_count())
    |> assign(:waiting, Comments.waiting_count())
    |> assign(:require?, Settings.get(:comments_require_confirmation))
  end

  # A comment the other desk deleted a moment ago is simply gone; the
  # list reloads either way.
  def handle_event("delete_comment", %{"id" => id}, socket) do
    Comments.delete_comment(id)
    {:noreply, load(socket)}
  end

  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
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
            waiting={@require? && is_nil(comment.address.confirmed_at)}
            article={comment.article}
          />
          <div
            :if={@total > length(@recent)}
            class="py-[11px] text-[12.5px] text-faint border-t border-hair"
          >
            and {@total - length(@recent)} more on their texts.
          </div>
        </div>
        <p class="note mt-[22px] max-w-[62ch]" id="commentsRule">{comment_rule(@require?)}</p>
      </div>
    </Layouts.app>
    """
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
