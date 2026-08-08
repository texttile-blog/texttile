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
     |> assign(:editing, nil)
     |> assign(:edit_error, nil)
     |> assign(:dialog, nil)
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

  # Delete asks first. Not because the trash could lose the comment -
  # it keeps it for a month - but because the words leave the text the
  # second the button is pressed, and readers are already reading them.
  def handle_event("delete_comment", %{"id" => id}, socket) do
    case Comments.get_comment(id) do
      nil -> {:noreply, load(socket)}
      comment -> {:noreply, assign(socket, :dialog, delete_dialog(comment))}
    end
  end

  # A comment another admin deleted a moment ago is simply gone; the
  # list reloads either way. The same for the restore and the release.
  def handle_event("confirm_delete_comment", %{"id" => id}, socket) do
    Comments.delete_comment(id)
    {:noreply, socket |> assign(:dialog, nil) |> close_edit() |> load()}
  end

  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
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
      {:error, changeset} -> {:noreply, assign(socket, :edit_error, edit_error(changeset))}
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
      crumb={gettext("Comments")}
      active="comments"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">{gettext("Comments")}</h1>
        <%!-- the counts carry the news, so they carry the weight. The
             number is bold inside the sentence, so the sentence
             travels as one string with the markup in it. --%>
        <p class="lead" id="commentsSub">
          <%= if @total == 0 do %>
            {gettext("The latest comments across all entries, newest first.")}
          <% else %>
            {Phoenix.HTML.raw(
              ngettext(
                "<b class='num'>1</b> comment across all entries, newest first.",
                "<b class='num'>%{count}</b> comments across all entries, newest first.",
                @total
              )
            )}
            <%= if @waiting == 0 do %>
              <%!-- not "every one is confirmed": a comment an admin let
                   through stands under its entry with an address that
                   never was --%>
              {gettext("Readers see every one of them.")}
            <% else %>
              {Phoenix.HTML.raw(
                ngettext(
                  "<b class='num'>1</b> comment waits for the reader to confirm the email address, so readers do not see it yet.",
                  "<b class='num'>%{count}</b> comments wait for the reader to confirm the email address, so readers do not see them yet.",
                  @waiting
                )
              )}
            <% end %>
          <% end %>
        </p>
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
            editing={@editing == to_string(comment.id)}
            error={@edit_error}
          />
          <div
            :if={@total > length(@recent)}
            class="py-[11px] text-[12.5px] text-faint border-t border-hair"
          >
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
          <div
            :if={@trashed_earlier > 0}
            class="py-[11px] text-[12.5px] text-faint border-t border-hair"
          >
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
