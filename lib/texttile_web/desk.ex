defmodule TexttileWeb.Desk do
  @moduledoc """
  The shared behaviour of every desk LiveView: presence in the wordmark
  menu. Each mounted tab tracks itself; the menu shows everybody else,
  one block per person, one jump per open tab.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope
  alias TexttileWeb.Presence

  @topic "desk"

  @views %{
    TexttileWeb.TextsLive => :texts,
    TexttileWeb.EditorLive => :editor,
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
      |> attach_hook(:desk_presence, :handle_info, &handle_info/2)
      |> attach_hook(:desk_actions, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  # New text lives in the wordmark menu, so it must work from every desk
  # view; this hook is the one handler behind all of them.
  defp handle_event("new_text", _params, socket) do
    {:ok, article} = Texttile.Articles.create_draft(socket.assigns.current_scope.user)
    {:halt, Phoenix.LiveView.push_navigate(socket, to: "/texts/#{article.id}")}
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
  defp handle_info({:desk_renamed, user_id}, socket) do
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
  Everybody at the desk except the current user: one entry per person,
  their open tabs as sessions with a label and a jump target.
  """
  def others(scope) do
    me = scope && to_string(scope.user.id)

    @topic
    |> Presence.list()
    |> Enum.reject(fn {key, _} -> key == me end)
    |> Enum.map(fn {_key, %{metas: metas}} ->
      %{
        name: metas |> List.first() |> Map.get(:name),
        sessions: Enum.map(metas, &%{label: activity(&1.view), path: path(&1.view)})
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Announces a changed displayed name. Every open tab of that user
  updates its own tracked presence meta and its scope on arrival.
  """
  def announce_rename(user_id) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:desk_renamed, user_id})
  end

  defp activity(:texts), do: "On the Texts overview"
  defp activity(:editor), do: "In a text"
  defp activity(:profile), do: "In the profile"
  defp activity(:settings), do: "In Settings"

  defp path(:profile), do: "/profile"
  defp path(:settings), do: "/settings"
  defp path(_view), do: "/"

  @doc "The ids of everybody with at least one open desk tab, as strings."
  def online_user_ids do
    @topic |> Presence.list() |> Map.keys()
  end
end
