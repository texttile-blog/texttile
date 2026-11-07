defmodule TexttileWeb.CommentsLive do
  @moduledoc """
  The Comments overview: every comment across all texts, newest first,
  one status at a time and one page at a time, each with the jump to its
  text, an Edit, a Release while it waits, and a Delete. The trash is
  one of the statuses, and it is the only place that shows a deleted
  comment. The filter carries the counts; the note at the foot carries
  the rule. Round-13's Comments screen.

  A box on each row and the line over the list act on many comments at
  once. With nothing ticked that line speaks of the whole filter, every
  page of it. What the admin ticked stays ticked over the pages, and
  goes when the filter changes. See ADR-030.
  """

  use TexttileWeb, :live_view

  import TexttileWeb.CommentComponents

  alias Texttile.Comments
  alias Texttile.Settings

  @bulk ~w(release delete restore)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Comments.subscribe()
      Settings.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Comments"))
     |> assign(:dialog, nil)
     |> assign(:status, "all")
     |> assign(:selected, MapSet.new())
     |> TexttileWeb.CommentModeration.attach(reload: &load/1)}
  end

  # The address holds the status and the page, so the way back from an
  # entry lands on the same comments.
  def handle_params(params, _uri, socket) do
    status = params["status"] || "all"

    {:noreply,
     socket
     |> assign(:selected, selected_for(socket, status))
     |> assign(:status, status)
     |> assign(:page, number(params["page"]) || 1)
     |> load()}
  end

  # A selection belongs to one filter: it says nothing about the next.
  defp selected_for(%{assigns: %{status: status, selected: selected}}, status), do: selected
  defp selected_for(_socket, _status), do: MapSet.new()

  # A status the setting took away, or one nobody ever wrote, reads as
  # all of them. Without the confirmation nothing gets released any
  # more, so that filter stays only while it still holds a comment.
  defp load(socket) do
    require? = Settings.get(:comments_require_confirmation)
    counts = Comments.status_counts()

    statuses =
      Comments.statuses(require?)
      |> Enum.reject(&(&1 == "released" and not require? and counts["released"] == 0))

    status = if socket.assigns.status in statuses, do: socket.assigns.status, else: "all"
    list = Comments.overview(status, socket.assigns.page)

    socket
    |> assign(:status, status)
    |> assign(:statuses, statuses)
    |> assign(:selected, still_there(socket.assigns.selected, status))
    |> assign(:counts, counts)
    |> assign(:comments, list.rows)
    |> assign(:page, list.page)
    |> assign(:pages, list.pages)
    |> assign(:require?, require?)
  end

  # A comment another admin took, or that left the filter, leaves the
  # selection too, so the number over the list is the number acted on.
  defp still_there(selected, status) do
    if MapSet.size(selected) == 0 do
      selected
    else
      MapSet.intersection(selected, MapSet.new(Comments.ids(status)))
    end
  end

  # What an address or a button sent as a number, or nil for anything else.
  defp number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp number(_value), do: nil

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

  def handle_event("toggle_comment", %{"id" => id}, socket) do
    id = number(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, socket |> assign(:selected, selected) |> load()}
  end

  # The whole filter, not the page: a wave is cleared in one go. With
  # everything ticked, the same box takes it all back.
  def handle_event("select_all", _params, socket) do
    all = MapSet.new(Comments.ids(socket.assigns.status))
    selected = if MapSet.equal?(all, socket.assigns.selected), do: MapSet.new(), else: all

    {:noreply, socket |> assign(:selected, selected) |> load()}
  end

  # The question fixes the list. A comment that arrives while it stands
  # is not one the admin said yes to.
  def handle_event("bulk", %{"action" => action}, socket) when action in @bulk do
    %{selected: selected, status: status} = socket.assigns
    ids = if MapSet.size(selected) == 0, do: Comments.ids(status), else: MapSet.to_list(selected)

    {:noreply, assign(socket, :dialog, bulk_dialog(action, ids))}
  end

  def handle_event("confirm_bulk", %{"id" => action}, socket) when action in @bulk do
    with %{ids: ids} <- socket.assigns.dialog, do: run_bulk(action, ids)

    {:noreply, socket |> assign(:dialog, nil) |> assign(:selected, MapSet.new()) |> load()}
  end

  def handle_info({:comment_posted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_deleted, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comment_changed, _comment}, socket), do: {:noreply, load(socket)}
  def handle_info({:comments_changed, _article_ids}, socket), do: {:noreply, load(socket)}
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
      <div class="admin-col">
        <div>
          <%!-- no count beside the heading: the All filter carries it --%>
          <h1 class="page-h" id="commentsTop">{gettext("Comments")}</h1>
          <nav
            class="flex gap-[3px] flex-wrap mt-0 sm:mt-6 mb-[8px]"
            id="commentFilter"
            aria-label={gettext("Filter by status")}
          >
            <.link
              :for={status <- @statuses}
              patch={comments_path(status, 1)}
              class={["seg-b", @status == status && "on"]}
              data-f={status}
            >
              {status_name(status)} <span class="num text-faint">{@counts[status]}</span>
            </.link>
          </nav>
        </div>
        <div>
          <div :if={@counts[@status] > 0} class="cmt-tools" id="commentTools">
            <label>
              <input
                type="checkbox"
                id="selectAll"
                checked={MapSet.size(@selected) == @counts[@status]}
                phx-click="select_all"
                aria-label={gettext("Select every comment of this filter")}
              />
              <span class="num">{selection_line(MapSet.size(@selected), @counts[@status])}</span>
            </label>
            <span class="sp"></span>
            <button
              :for={action <- bulk_actions(@status)}
              class={[
                "btn sm",
                MapSet.size(@selected) == 0 && "quiet",
                action == "delete" && "danger"
              ]}
              id={"bulk-#{action}"}
              phx-click="bulk"
              phx-value-action={action}
            >
              {bulk_label(action, MapSet.size(@selected), @counts[@status])}
            </button>
          </div>
          <div id="commentsList" class={@counts[@status] == 0 && "pt-[18px]"}>
            <p :if={@comments == []} class="note">{empty_line(@status)}</p>
            <p :if={@status == "trash" and @comments != []} class="note mb-[13px]">
              {trash_line(@counts["trash"])}
            </p>
            <%= if @status == "trash" do %>
              <.trashed_item
                :for={comment <- @comments}
                comment={comment}
                selected={MapSet.member?(@selected, comment.id)}
              />
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
                selected={MapSet.member?(@selected, comment.id)}
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

  # What the comments of a filter can still do.
  defp bulk_actions("waiting"), do: ["release", "delete"]
  defp bulk_actions("trash"), do: ["restore"]
  defp bulk_actions(_status), do: ["delete"]

  defp selection_line(0, all), do: gettext("Select all %{count}", count: all)
  defp selection_line(selected, _all), do: gettext("%{count} selected", count: selected)

  defp bulk_label("release", 0, all), do: gettext("Release all %{count}", count: all)
  defp bulk_label("release", selected, _all), do: gettext("Release %{count}", count: selected)
  defp bulk_label("delete", 0, all), do: gettext("Delete all %{count}", count: all)
  defp bulk_label("delete", selected, _all), do: gettext("Delete %{count}", count: selected)
  defp bulk_label("restore", 0, all), do: gettext("Restore all %{count}", count: all)
  defp bulk_label("restore", selected, _all), do: gettext("Restore %{count}", count: selected)

  defp run_bulk("release", ids), do: Comments.release_comments(ids)
  defp run_bulk("delete", ids), do: Comments.delete_comments(ids)
  defp run_bulk("restore", ids), do: Comments.restore_comments(ids)

  # The shape `<.ask>` reads, plus the list the answer acts on.
  defp bulk_dialog("release", ids) do
    %{
      title: ngettext("Release 1 comment?", "Release %{count} comments?", length(ids)),
      body: [
        gettext(
          "They stand under their entries at once. Their addresses stay unconfirmed, and nobody is mailed."
        ),
        gettext("There is no way back except Delete.")
      ],
      ok: gettext("Release"),
      event: "confirm_bulk",
      value: "release",
      ids: ids
    }
  end

  defp bulk_dialog("delete", ids) do
    %{
      title: ngettext("Delete 1 comment?", "Delete %{count} comments?", length(ids)),
      body: [
        gettext("They leave their entries at once, and the readers are not told."),
        gettext(
          "The trash keeps them for %{days} days. Restore puts them back where they stood; after that they are gone for good.",
          days: Comments.trash_days()
        )
      ],
      ok: gettext("Delete"),
      event: "confirm_bulk",
      value: "delete",
      ids: ids
    }
  end

  defp bulk_dialog("restore", ids) do
    %{
      title: ngettext("Restore 1 comment?", "Restore %{count} comments?", length(ids)),
      body: [gettext("They go back where they stood, and the same rule decides who sees them.")],
      ok: gettext("Restore"),
      event: "confirm_bulk",
      value: "restore",
      ids: ids
    }
  end

  defp status_name("all"), do: gettext("All")
  defp status_name("waiting"), do: gettext("Not confirmed yet")
  defp status_name("confirmed"), do: gettext("Confirmed")
  defp status_name("released"), do: gettext("Released")
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
