defmodule TexttileWeb.EditorLive do
  @moduledoc """
  One open text. Grows into the round-14 editor: the writing surface,
  the article settings, the Log and the Versions.
  """
  use TexttileWeb, :live_view

  alias Texttile.Articles

  def mount(%{"id" => id}, _session, socket) do
    article = Articles.get_article!(id)

    {:ok,
     socket
     |> assign(:article, article)
     |> assign(:page_title, page_title(article))}
  end

  defp page_title(%{title: ""}), do: "Untitled"
  defp page_title(%{title: title}), do: title

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={page_title(@article)}
      active="texts"
      others={@others}
    >
      <div class="max-w-[680px] mx-auto px-[14px] lg:px-[30px] pt-[22px] lg:pt-[30px] pb-10">
        <p class="note">The editor arrives in the next commit.</p>
      </div>
    </Layouts.app>
    """
  end
end
