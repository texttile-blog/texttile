defmodule TexttileWeb.CommentsLive do
  @moduledoc """
  The Comments overview: every comment across all texts, newest first,
  one status at a time and one page at a time, each with the jump to its
  text, an Edit, a Release while it waits, and a Delete. The trash is
  one of the statuses, and it is the only place that shows a deleted
  comment. The filter carries the counts; the note at the foot carries
  the rule. Round-13's Comments screen.
  """

  use TexttileWeb, :live_view

  import TexttileWeb.CommentComponents

  alias Texttile.Comments
  alias Texttile.Settings

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Comments.subscribe()
      Settings.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Comments"))
     |> assign(:dialog, nil)
     |> TexttileWeb.CommentModeration.attach(reload: &load/1)}
  end

  # The address holds the status and the page, so the way back from an
  # entry lands on the same comments.
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:status, params["status"])
     |> assign(:page, page_number(params["page"]))
     |> load()}
  end

  # A status the setting took away, or one nobody ever wrote, reads as
  # all of them.
  defp load(socket) do
    require? = Settings.get(:comments_require_confirmation)
    statuses = Comments.statuses(require?)
    status = if socket.assigns.status in statuses, do: socket.assigns.status, else: "all"
    list = Comments.overview(status, socket.assigns.page)

    socket
    |> assign(:status, status)
    |> assign(:statuses, statuses)
    |> assign(:counts, Comments.status_counts())
    |> assign(:comments, list.rows)
    |> assign(:page, list.page)
    |> assign(:pages, list.pages)
    |> assign(:require?, require?)
  end

  defp page_number(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page_number(_page), do: 1

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
        <h1 class="page-h" id="commentsTop">{gettext("Comments")}</h1>
        <nav
          class="flex gap-[3px] flex-wrap py-3 mt-[14px] mb-[18px] border-y border-rule"
          id="commentFilter"
          aria-label={gettext("Filter by status")}
        >
          <.link
            :for={status <- @statuses}
            patch={comments_path(status, 1)}
            class={["seg-b", @status == status && "on"]}
            data-f={status}
          >
            {status_name(status)} <span class="num opacity-60">{@counts[status]}</span>
          </.link>
        </nav>
        <div id="commentsList">
          <p :if={@comments == []} class="note">{empty_line(@status)}</p>
          <p :if={@status == "trash" and @comments != []} class="note mb-[13px]">
            {trash_line(@counts["trash"])}
          </p>
          <%= if @status == "trash" do %>
            <.trashed_item :for={comment <- @comments} comment={comment} />
          <% else %>
            <%!-- the address behind a comment is loaded with it, so the
                 name can be the way to write back --%>
            <.comment_item
              :for={comment <- @comments}
              comment={comment}
              waiting={Comments.waiting?(comment, @require?)}
              article={comment.article}
              editing={@editing_comment == to_string(comment.id)}
              error={@comment_error}
            />
          <% end %>
        </div>
        <%!-- the three cells of the Entries pager. A step lands on the
             top of the list: the pager stands at its foot, and a patch
             alone would leave the admin down there. --%>
        <nav
          :if={@pages > 1}
          class="f-pager mt-[18px] pt-4 border-t border-rule"
          id="pager"
          aria-label={gettext("Pages")}
        >
          <span>
            <.link
              :if={@page > 1}
              class="btn sm"
              id="prev-page"
              patch={comments_path(@status, @page - 1) <> "#commentsTop"}
            >
              {gettext("Newer")}
            </.link>
          </span>
          <span class="note num">
            {gettext("Page %{page} of %{pages}", page: @page, pages: @pages)}
          </span>
          <span>
            <.link
              :if={@page < @pages}
              class="btn sm"
              id="next-page"
              patch={comments_path(@status, @page + 1) <> "#commentsTop"}
            >
              {gettext("Older")}
            </.link>
          </span>
        </nav>
        <p class="note mt-[22px]" id="commentsRule">{comment_rule(@require?)}</p>
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

  # The first page of everything stays the bare address, the one the
  # mails and the menu link to.
  defp comments_path(status, page) do
    params =
      for {key, value} <- [status: status, page: page], value not in ["all", 1], do: {key, value}

    ~p"/admin/comments?#{params}"
  end

  defp status_name("all"), do: gettext("All")
  defp status_name("waiting"), do: gettext("Not confirmed yet")
  defp status_name("confirmed"), do: gettext("Confirmed")
  defp status_name("released"), do: gettext("Let through")
  defp status_name("trash"), do: gettext("Trash")

  defp empty_line("all") do
    gettext("No comments yet, anywhere. Every comment a reader sends shows up here.")
  end

  defp empty_line(_status), do: gettext("No comments here.")

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
