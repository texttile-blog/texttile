defmodule TexttileWeb.Desk do
  @moduledoc """
  The shared behaviour of every desk LiveView: presence in the wordmark
  menu. Each mounted tab tracks itself; the menu shows everybody else,
  one block per person, one jump per open tab.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Texttile.Accounts
  alias TexttileWeb.Presence

  @topic "desk"

  @views %{
    TexttileWeb.TextsLive => :texts,
    TexttileWeb.ProfileLive => :profile
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
      |> attach_hook(:desk_presence, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_info(%Phoenix.Socket.Broadcast{topic: @topic, event: "presence_diff"}, socket) do
    {:halt, assign(socket, :others, others(socket.assigns.current_scope))}
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
  Renaming yourself changes what the others read, live: the tracked
  meta of every tab of this process follows the new name.
  """
  def rename(scope, name) do
    Presence.update(self(), @topic, to_string(scope.user.id), &Map.put(&1, :name, name))
  end

  defp activity(:texts), do: "On the Texts overview"
  defp activity(:profile), do: "In the profile"

  defp path(:profile), do: "/profile"
  defp path(_view), do: "/"
end
