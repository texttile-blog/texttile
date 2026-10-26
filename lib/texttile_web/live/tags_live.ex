defmodule TexttileWeb.TagsLive do
  @moduledoc "Manage tags across all entries, with inline renaming and confirmed deletion."
  use TexttileWeb, :live_view

  alias Texttile.Articles

  def mount(_params, _session, socket) do
    if connected?(socket), do: Articles.subscribe_admin()

    {:ok,
     socket
     |> assign(:page_title, gettext("Tags"))
     |> assign(:editing, nil)
     |> assign(:confirm_tag, nil)
     |> assign(:error, nil)
     |> assign(:form, to_form(%{"name" => ""}, as: :tag))
     |> load()}
  end

  def handle_event("edit_tag", %{"tag" => tag}, socket) do
    {:noreply,
     socket
     |> assign(:editing, tag)
     |> assign(:error, nil)
     |> assign(:form, to_form(%{"name" => tag}, as: :tag))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, error: nil)}
  end

  def handle_event("rename_tag", %{"tag" => %{"name" => name}}, socket) do
    if socket.assigns.editing do
      case Articles.rename_tag(socket.assigns.editing, name) do
        {:ok, count} ->
          {:noreply,
           socket
           |> assign(editing: nil, error: nil)
           |> load()
           |> put_flash(
             :info,
             ngettext("Tag renamed in 1 entry.", "Tag renamed in %{count} entries.", count)
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:form, to_form(%{"name" => name}, as: :tag))
           |> assign(:error, rename_error(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("ask_delete_tag", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :confirm_tag, tag)}
  end

  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :confirm_tag, nil)}
  end

  def handle_event("delete_tag", _params, socket) do
    if tag = socket.assigns.confirm_tag do
      count = Articles.delete_tag(tag)

      {:noreply,
       socket
       |> assign(:confirm_tag, nil)
       |> load()
       |> put_flash(
         :info,
         ngettext("Tag removed from 1 entry.", "Tag removed from %{count} entries.", count)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({event, _entry}, socket) when event in [:article_changed, :article_deleted] do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    tags = Articles.tag_counts()
    editing = socket.assigns.editing
    socket = assign(socket, :tags, tags)

    if editing && not Enum.any?(tags, fn {tag, _} -> tag == editing end) do
      socket
      |> assign(editing: nil, error: nil)
      |> put_flash(:info, gettext("This tag changed while you were editing it."))
    else
      socket
    end
  end

  defp rename_error(:invalid_tag), do: gettext("Enter one tag name without commas.")
  defp rename_error(:tag_exists), do: gettext("This tag already exists. Choose another name.")
  defp rename_error(:not_found), do: gettext("This tag no longer exists.")

  # Unlike a slug, this ID also distinguishes punctuation and accented names.
  defp tag_id(tag), do: tag |> String.downcase() |> URI.encode(&URI.char_unreserved?/1)

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Tags")}
      active="tags"
      others={@others}
    >
      <:bar><Layouts.view_site /></:bar>
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap mb-5">
          <h1 class="page-h">{gettext("Tags")}</h1>
          <span class="note num" id="tagsCount">
            {ngettext("1 tag", "%{count} tags", length(@tags))}
          </span>
        </div>
        <div id="tagsList">
          <p :if={@tags == []} class="note">
            {gettext("No entry carries a tag yet. Add tags in an entry's settings.")}
          </p>
          <div
            :for={{tag, count} <- @tags}
            id={"tagrow-#{tag_id(tag)}"}
            class="py-[14px] border-b border-hair flex items-center gap-[10px] flex-wrap"
          >
            <b class="text-[14.5px] break-words min-w-0 max-w-full">{tag}</b>
            <span class="note">{ngettext("1 entry", "%{count} entries", count)}</span>
            <div :if={@editing != tag} class="ml-auto flex gap-2">
              <button
                type="button"
                class="btn sm"
                id={"edit-tag-#{tag_id(tag)}"}
                phx-click="edit_tag"
                phx-value-tag={tag}
              >
                {gettext("Edit")}
              </button>
              <button
                type="button"
                class="btn sm"
                id={"delete-tag-#{tag_id(tag)}"}
                phx-click="ask_delete_tag"
                phx-value-tag={tag}
              >
                {gettext("Delete")}
              </button>
            </div>
            <.form
              :if={@editing == tag}
              for={@form}
              id="rename-tag-form"
              class="w-full pt-2"
              phx-submit="rename_tag"
            >
              <label for="tag-name" class="lab block mb-[3px]">{gettext("Name")}</label>
              <input
                type="text"
                id="tag-name"
                phx-mounted={JS.focus()}
                name={@form[:name].name}
                value={@form[:name].value}
                autocomplete="off"
                aria-describedby={if @error, do: "tag-scope tag-error", else: "tag-scope"}
                aria-invalid={@error != nil}
              />
              <p class="note mt-2" id="tag-scope">
                {ngettext("Changes in 1 entry.", "Changes in all %{count} entries.", count)}
              </p>
              <p :if={@error} class="text-[13px] text-julia mt-2" id="tag-error" role="alert">
                {@error}
              </p>
              <div class="flex gap-2 mt-4">
                <button type="submit" class="btn solid" phx-disable-with={gettext("Renaming…")}>
                  {gettext("Rename")}
                </button>
                <button type="button" class="btn quiet" id="cancel-tag-edit" phx-click="cancel_edit">
                  {gettext("Cancel")}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
      <.ask
        :if={@confirm_tag}
        heading={gettext("Delete the tag %{tag}?", tag: @confirm_tag)}
        ok={gettext("Delete the tag")}
        on_ok="delete_tag"
      >
        <p>
          {gettext(
            "This removes the tag from every entry and closes its archive page. The entries and their other tags stay."
          )}
        </p>
        <p class="mt-3">
          {gettext("There is no undo. To have the tag back, write it on an entry again.")}
        </p>
      </.ask>
    </Layouts.app>
    """
  end
end
