defmodule TexttileWeb.CommentModeration do
  @moduledoc """
  What an admin does to a comment, wherever they stand.

  Two screens moderate comments: the Comments overview across all
  entries, and the Comments tab of one open entry. The actions are the
  same six - ask to delete, delete, release, and the edit family - and
  so are the rules: delete asks first, and a comment somebody else
  deleted a moment ago is no error, the list simply reloads.

  A screen attaches this in `mount/3` and says two things: which
  comments it may touch, and how it reloads its list. Everything else
  is answered here once. The dialog goes into `:dialog`, the open edit
  into `:editing_comment` and `:comment_error`, and the screen's
  template draws them as it likes.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]
  import TexttileWeb.CommentComponents, only: [delete_dialog: 1, edit_error: 1]

  alias Texttile.Comments

  @events ~w(delete_comment confirm_delete_comment release_comment start_edit cancel_edit save_comment)

  @doc """
  Attaches the moderation events to a LiveView.

  Options:

    * `:reload` (required) - how this screen reloads its comments after
      an action, `fn socket -> socket end`.
    * `:scope` - which comments the screen may touch: `:all` (default),
      or `{:article, fn socket -> article_id end}` for the one open
      entry. Anything outside the scope is left alone without a word.
  """
  def attach(socket, opts) do
    scope = Keyword.get(opts, :scope, :all)
    reload = Keyword.fetch!(opts, :reload)

    socket
    |> assign(:editing_comment, nil)
    |> assign(:comment_error, nil)
    |> attach_hook(:comment_moderation, :handle_event, fn
      event, params, socket when event in @events ->
        {:halt, handle(event, params, socket, scope, reload)}

      _event, _params, socket ->
        {:cont, socket}
    end)
  end

  # Delete asks first. Not because the trash could lose the comment -
  # it keeps it for a month - but because the words leave the text the
  # second the button is pressed, and readers are already reading them.
  defp handle("delete_comment", %{"id" => id}, socket, scope, reload) do
    case fetch(socket, id, scope) do
      nil -> reload.(socket)
      comment -> assign(socket, :dialog, delete_dialog(comment))
    end
  end

  defp handle("confirm_delete_comment", %{"id" => id}, socket, scope, reload) do
    with %{} = comment <- fetch(socket, id, scope), do: Comments.delete_comment(comment.id)
    socket |> assign(:dialog, nil) |> close_edit() |> reload.()
  end

  defp handle("release_comment", %{"id" => id}, socket, scope, reload) do
    with %{} = comment <- fetch(socket, id, scope), do: Comments.release_comment(comment.id)
    reload.(socket)
  end

  # One comment stands open at a time; opening another closes the first
  # and drops what it said about the last save.
  defp handle("start_edit", %{"id" => id}, socket, _scope, _reload) do
    socket |> assign(:editing_comment, to_string(id)) |> assign(:comment_error, nil)
  end

  defp handle("cancel_edit", _params, socket, _scope, _reload) do
    close_edit(socket)
  end

  defp handle("save_comment", %{"comment_id" => id, "body" => body}, socket, scope, reload) do
    result =
      case fetch(socket, id, scope) do
        nil -> {:error, :gone}
        comment -> Comments.edit_comment(comment.id, body)
      end

    case result do
      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :comment_error, edit_error(changeset))

      _saved_or_gone ->
        socket |> close_edit() |> reload.()
    end
  end

  defp close_edit(socket) do
    socket |> assign(:editing_comment, nil) |> assign(:comment_error, nil)
  end

  defp fetch(_socket, id, :all), do: Comments.get_comment(id)

  defp fetch(socket, id, {:article, article_id}) do
    article_id = article_id.(socket)

    case Comments.get_comment(id) do
      %{article_id: ^article_id} = comment -> comment
      _other -> nil
    end
  end
end
