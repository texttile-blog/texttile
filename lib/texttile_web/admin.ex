defmodule TexttileWeb.Admin do
  @moduledoc """
  The shared behaviour of every admin LiveView: presence in the wordmark
  menu. Each mounted tab tracks itself; the menu shows everybody else,
  one block per person, one jump per open tab.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope
  alias TexttileWeb.Presence

  @topic "admin"

  @views %{
    TexttileWeb.TextsLive => :texts,
    TexttileWeb.EditorLive => :editor,
    TexttileWeb.CommentsLive => :comments,
    TexttileWeb.NewsletterLive => :newsletter,
    TexttileWeb.ProfileLive => :profile,
    TexttileWeb.SettingsLive => :settings
  }

  def on_mount(:track_presence, _params, _session, socket) do
    view = Map.get(@views, socket.view)
    scope = socket.assigns.current_scope

    if connected?(socket) && scope && view do
      Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)

      {:ok, _} =
        Presence.track(self(), @topic, to_string(scope.user.id), %{
          view: view,
          name: Accounts.display_name(scope.user)
        })
    end

    socket =
      socket
      |> assign(:others, others(scope))
      |> assign(:online_ids, online_user_ids())
      |> attach_hook(:admin_presence, :handle_info, &handle_info/2)
      |> attach_hook(:admin_actions, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  # New text lives in the wordmark menu, so it must work from every
  # admin view; this hook is the one handler behind all of them.
  defp handle_event("new_text", _params, socket) do
    {:ok, article} = Texttile.Articles.create_draft(socket.assigns.current_scope.user)
    {:halt, Phoenix.LiveView.push_navigate(socket, to: "/admin/texts/#{article.id}")}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info(%Phoenix.Socket.Broadcast{topic: @topic, event: "presence_diff"}, socket) do
    {:halt,
     socket
     |> assign(:others, others(socket.assigns.current_scope))
     |> assign(:online_ids, online_user_ids())}
  end

  # Somebody's displayed name changed. Every tab of that person reloads
  # its own scope and rewrites its own tracked meta; everybody else then
  # sees the new name through the presence diffs that follow.
  defp handle_info({:admin_renamed, user_id}, socket) do
    scope = socket.assigns.current_scope

    if scope && scope.user.id == user_id do
      user = Accounts.get_user!(user_id)
      scope = Scope.for_user(user, scope.session_token)

      Presence.update(
        self(),
        @topic,
        to_string(user_id),
        &Map.put(&1, :name, Accounts.display_name(user))
      )

      {:halt,
       socket
       |> assign(:current_scope, scope)
       |> assign(:others, others(scope))}
    else
      {:halt, socket}
    end
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  @doc """
  Everybody in the admin area except the current user: one entry per
  person, their open tabs as sessions with a label and a jump target. A
  session in a text carries its `text_id`, so the editor knows who reads
  along.
  """
  def others(scope) do
    me = scope && to_string(scope.user.id)

    @topic
    |> Presence.list()
    |> Enum.reject(fn {key, _} -> key == me end)
    |> Enum.map(fn {_key, %{metas: metas}} ->
      %{
        name: metas |> List.first() |> Map.get(:name),
        sessions:
          Enum.map(metas, &%{label: activity(&1), path: path(&1), text_id: Map.get(&1, :text_id)})
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  An open editor announces which text it is in and whether it writes or
  reads along; the wordmark menu and the other editor's banner read it.
  """
  def update_activity(scope, extra) do
    Presence.update(self(), @topic, to_string(scope.user.id), &Map.merge(&1, extra))
  end

  @doc """
  Announces a changed displayed name. Every open tab of that user
  updates its own tracked presence meta and its scope on arrival.
  """
  def announce_rename(user_id) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:admin_renamed, user_id})
  end

  defp activity(%{view: :editor} = meta) do
    title = Map.get(meta, :text_title) || "Untitled"
    if Map.get(meta, :writing), do: "Writing in “#{title}”", else: "In “#{title}”"
  end

  defp activity(%{view: :texts}), do: "On the Texts overview"
  defp activity(%{view: :comments}), do: "In the comments"
  defp activity(%{view: :newsletter}), do: "In the newsletter"
  defp activity(%{view: :profile}), do: "In the profile"
  defp activity(%{view: :settings}), do: "In Settings"

  defp path(%{view: :editor} = meta) do
    case Map.get(meta, :text_id) do
      nil -> "/admin"
      id -> "/admin/texts/#{id}"
    end
  end

  defp path(%{view: :comments}), do: "/admin/comments"
  defp path(%{view: :newsletter}), do: "/admin/newsletter"
  defp path(%{view: :profile}), do: "/admin/profile"
  defp path(%{view: :settings}), do: "/admin/settings"
  defp path(_meta), do: "/admin"

  @doc "The ids of everybody with at least one open admin tab, as strings."
  def online_user_ids do
    @topic |> Presence.list() |> Map.keys()
  end
end
