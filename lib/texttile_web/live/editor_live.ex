defmodule TexttileWeb.EditorLive do
  @moduledoc """
  One open text: the round-14 editor. The writing surface in the middle
  column with the Text, Log and Versions tabs; the article settings in
  the side column. The tiles block returns with the gallery.

  The title and the body belong to whoever holds the soft lock
  (`Texttile.Articles.Lock`); the article settings and the publish
  controls stay open to every admin all the time.
  """
  use TexttileWeb, :live_view

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Articles.Lock

  ## Mount

  def mount(%{"id" => id}, _session, socket) do
    article = Articles.get_article!(id)
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:article, article)
      |> assign(:tab, "text")
      |> assign(:state_menu, false)
      |> assign(:dialog, nil)
      |> assign(:saved_at, DateTime.to_unix(article.updated_at, :millisecond))
      |> assign(:saved_note, nil)
      |> assign(:saved_until, 0)
      |> assign(:holds_lock, true)
      |> assign(:holder, nil)
      |> assign(:versions, Articles.versions(article))
      |> assign(:log, Articles.log(article))

    socket =
      if connected?(socket) do
        Articles.subscribe(article.id)

        case Lock.acquire(article.id, user.id, self()) do
          :ok -> assign(socket, :holds_lock, true)
          {:held, holder} -> socket |> assign(:holds_lock, false) |> assign(:holder, holder)
        end
      else
        socket
      end

    {:ok, assign(socket, :page_title, title_of(article))}
  end

  def terminate(_reason, socket) do
    if socket.assigns[:article], do: Lock.release(socket.assigns.article.id, self())
    :ok
  end

  ## Events · the text

  def handle_event("title_changed", %{"title" => title}, socket) do
    if socket.assigns.holds_lock do
      {:ok, article} = Articles.update_text(socket.assigns.article, %{title: title})
      Lock.ping(article.id, self())
      {:noreply, socket |> assign(:article, article) |> mark_saved()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("body_changed", %{"text" => text}, socket) do
    if socket.assigns.holds_lock do
      {:ok, article} = Articles.update_text(socket.assigns.article, %{body: text})
      Lock.ping(article.id, self())
      {:noreply, socket |> assign(:article, article) |> mark_saved()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("editor_activity", _params, socket) do
    if socket.assigns.holds_lock, do: Lock.ping(socket.assigns.article.id, self())
    {:noreply, socket}
  end

  def handle_event("save_version", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    case Articles.save_version(article, scope.user) do
      {:ok, _version} -> {:noreply, mark_saved(socket, "Version saved · just now")}
      :unchanged -> {:noreply, mark_saved(socket, "Nothing changed since the last version")}
    end
  end

  def handle_event("restore_version", %{"id" => id}, socket) do
    %{article: article, current_scope: scope, versions: versions} = socket.assigns

    cond do
      not socket.assigns.holds_lock ->
        {:noreply, mark_saved(socket, "Take the text over first; restoring needs it")}

      version = Enum.find(versions, &(to_string(&1.id) == id)) ->
        {:ok, article} = Articles.restore_version(article, version, scope.user)

        {:noreply,
         socket
         |> assign(:article, article)
         |> push_event("sync_body", %{text: article.body})
         |> mark_saved("Version from #{stamp(version.inserted_at)} restored")}

      true ->
        {:noreply, socket}
    end
  end

  ## Events · the takeover

  def handle_event("ask_takeover", _params, socket) do
    article = socket.assigns.article

    case Lock.state(article.id) do
      :free ->
        {:noreply, refresh_lock(socket)}

      %{pid: pid} when pid == self() ->
        {:noreply, refresh_lock(socket)}

      holder ->
        name = holder_name(holder)

        {:noreply,
         assign(socket, :dialog, %{
           id: "takeover",
           title: "Take the text over from #{name}?",
           body: [
             activity_line(name, holder),
             "A takeover stops that mid-sentence. The title and the body turn read-only on the other side, and a note says who took the text. Nothing is lost, and the text can go straight back."
           ],
           ok: "Take over the text",
           event: "confirm_takeover"
         })}
    end
  end

  def handle_event("confirm_takeover", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    socket = assign(socket, :dialog, nil)

    case Lock.takeover(article.id, scope.user.id, self()) do
      :ok -> {:noreply, refresh_lock(socket)}
      :pending -> {:noreply, socket}
    end
  end

  ## Events · publish and its undos

  def handle_event("publish", _params, socket) do
    article = socket.assigns.article
    holder = Lock.state(article.id)

    if socket.assigns.holds_lock or holder == :free do
      {:noreply, do_publish(socket, [])}
    else
      # not a merge problem, a side-effect problem: the person writing
      # right now deserves a word before their half-finished draft goes
      # public
      name = holder_name(holder)

      {:noreply,
       assign(socket, :dialog, %{
         id: "publish-anyway",
         title: "#{name} is editing this text right now",
         body: ["Publish it anyway, as it stands this second?"],
         ok: "Publish anyway",
         event: "do_publish"
       })}
    end
  end

  def handle_event("do_publish", _params, socket) do
    {:noreply, socket |> assign(:dialog, nil) |> do_publish([])}
  end

  def handle_event("publish_now", _params, socket) do
    {:noreply, do_publish(socket, force: true)}
  end

  def handle_event("unpublish", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    was = article.status
    {:ok, article} = Articles.unpublish(article, scope.user)

    {:noreply,
     socket
     |> assign(:article, article)
     |> assign(:state_menu, false)
     |> reload_history()
     |> mark_saved(
       if(was == "scheduled",
         do: "Unscheduled · a draft again",
         else: "Unpublished · a draft again"
       )
     )}
  end

  ## Events · article settings

  def handle_event("settings_changed", %{"_target" => ["publish_date" | _]} = params, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    was = article.status

    date =
      case Date.from_iso8601(params["publish_date"] || "") do
        {:ok, date} -> date
        _ -> nil
      end

    {:ok, article} = Articles.set_publish_date(article, scope.user, date)

    note =
      cond do
        was != "draft" and article.status == "draft" ->
          if was == "scheduled",
            do: "The date is empty · unscheduled, a draft again",
            else: "The date is empty · unpublished, a draft again"

        true ->
          nil
      end

    {:noreply, socket |> assign(:article, article) |> reload_history() |> mark_saved(note)}
  end

  def handle_event("settings_changed", %{"_target" => [field | _]} = params, socket)
      when field in ~w(type tags slug allow_comments protected notify_on_publish) do
    %{article: article} = socket.assigns

    case Articles.update_settings(article, Map.take(params, [field])) do
      {:ok, article} ->
        {:noreply, socket |> assign(:article, article) |> mark_saved()}

      {:error, _changeset} ->
        {:noreply, mark_saved(socket, "That address is taken by another text")}
    end
  end

  def handle_event("settings_changed", _params, socket), do: {:noreply, socket}

  ## Events · chrome

  def handle_event("set_tab", %{"tab" => tab}, socket)
      when tab in ~w(text log versions) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("toggle_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, !socket.assigns.state_menu)}
  end

  def handle_event("close_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, false)}
  end

  def handle_event("ask_delete", _params, socket) do
    article = socket.assigns.article
    address = "#{TexttileWeb.Endpoint.host()}/#{article.slug || Articles.slugify(article.title)}"

    live_line =
      if article.status == "published",
        do: [
          "The text is live. From now on, a reader who follows an old link to #{address} gets a 404 page."
        ],
        else: []

    {:noreply,
     socket
     |> assign(:state_menu, false)
     |> assign(:dialog, %{
       id: "delete",
       title: ~s(Delete "#{title_of(article)}"?),
       body:
         [
           "This deletes the text and everything that belongs to it: the title and the body, the images in the text, every saved version and the whole Log."
         ] ++ live_line ++ ["There is no undo."],
       ok: "Delete the text",
       event: "confirm_delete"
     })}
  end

  def handle_event("confirm_delete", _params, socket) do
    article = socket.assigns.article
    {:ok, _} = Articles.delete_article(article)

    {:noreply,
     socket
     |> put_flash(
       :info,
       ~s("#{title_of(article)}" is deleted. Its versions and its log went with it.)
     )
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  defp do_publish(socket, opts) do
    %{article: article, current_scope: scope} = socket.assigns
    {:ok, article} = Articles.publish(article, scope.user, opts)

    note =
      if article.status == "scheduled" do
        "Scheduled for #{article.publish_date}" <>
          if(will_notify?(article),
            do: " · subscribers get the email then",
            else: " · no email will go out"
          )
      else
        "Published just now" <>
          if(will_notify?(article), do: "", else: ", quietly · no email sent")
      end

    socket
    |> assign(:article, article)
    |> assign(:state_menu, false)
    |> reload_history()
    |> mark_saved(note)
  end

  # What the takeover dialog owes the person asking: not a generic "are
  # you sure", but who holds the text and how active they are.
  defp activity_line(name, holder) do
    now = DateTime.utc_now()
    idle = DateTime.diff(now, holder.last_keystroke_at, :second)

    if idle <= 30 do
      "#{name} is typing right now."
    else
      open_for = minutes_in_words(DateTime.diff(now, holder.acquired_at, :second))
      "#{name} has had this open for #{open_for} but hasn't typed for #{minutes_in_words(idle)}."
    end
  end

  defp minutes_in_words(seconds) when seconds < 60, do: "under a minute"
  defp minutes_in_words(seconds) when seconds < 120, do: "a minute"
  defp minutes_in_words(seconds), do: "#{div(seconds, 60)} minutes"

  ## PubSub and lock messages

  def handle_info({:text_changed, %{id: id} = article}, socket) do
    cond do
      id != socket.assigns.article.id or socket.assigns.holds_lock ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> assign(:article, article)
         |> push_event("sync_body", %{text: article.body})}
    end
  end

  def handle_info({:article_changed, %{id: id} = incoming}, socket) do
    if id == socket.assigns.article.id do
      current = socket.assigns.article

      article =
        if socket.assigns.holds_lock,
          do: %{incoming | title: current.title, body: current.body},
          else: incoming

      {:noreply, assign(socket, :article, article)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:article_deleted, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply,
       socket
       |> put_flash(:info, "The text was deleted while you had it open.")
       |> push_navigate(to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:versions_changed, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply, assign(socket, :versions, Articles.versions(socket.assigns.article))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:log_changed, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply, assign(socket, :log, Articles.log(socket.assigns.article))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:lock_changed, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply, refresh_lock(socket)}
    else
      {:noreply, socket}
    end
  end

  # The lock asks this holder to flush before a takeover. The server
  # state already carries every autosaved keystroke; anything younger
  # sits in the client debounce and is small enough to let go. Snapshot
  # what stands, then let the transfer go ahead.
  def handle_info({:lock_flush, id}, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    if id == article.id, do: Articles.snapshot(article, scope.user)
    Lock.flushed(id)
    {:noreply, socket}
  end

  def handle_info({:lock_taken, id, _by_user_id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply, socket |> refresh_lock() |> mark_saved(taken_note(socket))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:lock_granted, id}, socket) do
    if id == socket.assigns.article.id do
      %{article: article, current_scope: scope} = socket.assigns

      # the safety net of the handover: if the displaced side could not
      # flush, snapshot what the database holds. Byte-identical to the
      # flush's own snapshot means nothing extra is kept.
      displaced =
        case socket.assigns.holder do
          %{user_id: user_id} -> Accounts.get_user!(user_id)
          _ -> nil
        end

      if displaced, do: Articles.snapshot(article, displaced)
      Articles.push_log(article, scope.user, "took over the text")

      note =
        if displaced,
          do: "You have the text · #{Accounts.display_name(displaced)} was told",
          else: "You have the text"

      {:noreply, socket |> refresh_lock() |> mark_saved(note)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp taken_note(socket) do
    case Lock.state(socket.assigns.article.id) do
      %{user_id: _} = holder -> "#{holder_name(holder)} is editing now. Your changes are saved."
      :free -> "Your changes are saved."
    end
  end

  defp refresh_lock(socket) do
    article = socket.assigns.article

    {holds, holder} =
      case Lock.state(article.id) do
        :free ->
          case Lock.acquire(article.id, socket.assigns.current_scope.user.id, self()) do
            :ok -> {true, nil}
            {:held, holder} -> {false, holder}
          end

        %{pid: pid} = holder ->
          {pid == self(), holder}
      end

    socket
    |> assign(:holds_lock, holds)
    |> assign(:holder, unless(holds, do: holder))
    |> push_event("set_readonly", %{readOnly: !holds})
  end

  ## Saved state

  @note_ms 4600

  defp mark_saved(socket, note \\ nil) do
    now = System.system_time(:millisecond)

    socket
    |> assign(:saved_at, now)
    |> assign(:saved_note, note)
    |> assign(:saved_until, if(note, do: now + @note_ms, else: 0))
  end

  defp reload_history(socket) do
    socket
    |> assign(:versions, Articles.versions(socket.assigns.article))
    |> assign(:log, Articles.log(socket.assigns.article))
  end

  ## Render

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={title_of(@article)}
      active="texts"
      others={@others}
    >
      <:bar>
        <span class={["stamp hidden sm:inline", @article.status]} id="stamp">
          {@article.status}
        </span>
        <span
          class="hidden md:inline text-[12.5px] text-faint whitespace-nowrap num"
          id="state"
          phx-hook="SavedTicker"
          data-at={@saved_at}
          data-note={@saved_note}
          data-note-until={@saved_until}
        >
          Last saved · just now
        </span>
        <button
          class="btn hidden sm:inline-flex"
          id="btnSave"
          phx-click="save_version"
          title="Keep a version of the title and the body as they stand now"
        >
          Save version
        </button>
        <span
          class={["split", if(@article.status == "draft", do: "solid", else: "calm")]}
          id="stateBtn"
        >
          <%= if @article.status == "draft" do %>
            <button
              class="main"
              phx-click="publish"
              title="Publishes the text now. A future publish date in the settings schedules it instead."
            >
              Publish
            </button>
            <span class="div" aria-hidden="true"></span>
            <button
              class="chev"
              id="stateChev"
              phx-click="toggle_state_menu"
              aria-haspopup="true"
              aria-expanded={to_string(@state_menu)}
              aria-label="More actions for this draft"
            >
              <.chevron_icon />
            </button>
          <% else %>
            <button
              class="main one"
              id="stateChev"
              phx-click="toggle_state_menu"
              aria-haspopup="true"
              aria-expanded={to_string(@state_menu)}
              aria-label={"#{String.capitalize(@article.status)}, state actions"}
            >
              {String.capitalize(@article.status)}
              <span class="cv" aria-hidden="true"><.chevron_icon /></span>
            </button>
          <% end %>
        </span>
      </:bar>

      <div
        :if={@state_menu}
        class="pop min-w-[180px]"
        id="stateMenu"
        phx-hook="PlacePop"
        data-anchor="#stateBtn"
        data-align="right"
        phx-click-away="close_state_menu"
        phx-window-keydown="close_state_menu"
        phx-key="escape"
      >
        <button class="row sm:hidden" phx-click="save_version">Save version</button>
        <%= if @article.status == "scheduled" do %>
          <button class="row" phx-click="publish_now">Publish now</button>
          <button class="row" phx-click="unpublish">Unschedule</button>
        <% end %>
        <%= if @article.status == "published" do %>
          <button class="row" phx-click="unpublish">Unpublish</button>
        <% end %>
        <button class="row" phx-click="ask_delete">Delete this text</button>
      </div>

      <p :if={@saved_note} class="state-live" id="stateLine" role="status" aria-live="polite">
        {@saved_note}
      </p>

      <div class="xl:grid xl:grid-cols-[minmax(0,1fr)_380px] lg:grid lg:grid-cols-[minmax(0,1fr)_320px] lg:h-[calc(100dvh-52px)]">
        <div class="lg:overflow-y-auto min-w-0" id="textCol">
          <div class="max-w-[680px] mx-auto px-[14px] lg:px-[30px] pt-[22px] lg:pt-[30px] pb-10 lg:pb-[110px]">
            <%!-- the lock banner: the only place that tells the lock
                 story. There is no button on it, because clicking into
                 the title or the body already asks. --%>
            <div
              :if={!@holds_lock && @holder}
              class="flex items-baseline gap-[9px] flex-wrap rounded-[5px] px-[13px] py-2 text-[13px] mb-5 bg-livetint text-livetext"
              id="jbar"
              style="box-shadow: inset 0 0 0 1px var(--tt-liveline)"
            >
              <span class="flex items-center gap-[9px] flex-none">
                <span class="dot live text-julia"></span>
                <b class="text-julia">{holder_name(@holder)}</b>
              </span>
              <span class="opacity-85 flex-1 min-w-[220px]">
                writes the text now, and you see every word arrive. Click into the title or the body to take the text over. The article settings stay open to every admin, at the same time.
              </span>
            </div>

            <nav
              class="flex gap-0.5 border-b border-rule mb-6 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
              aria-label="Text sections"
            >
              <button
                :for={{tab, label} <- [{"text", "Text"}, {"log", "Log"}, {"versions", "Versions"}]}
                class={["tab", @tab == tab && "on"]}
                phx-click="set_tab"
                phx-value-tab={tab}
              >
                {label}
                <span :if={tab == "versions" && @versions != []} class="cnt">
                  {length(@versions)}
                </span>
              </button>
            </nav>

            <div :if={@tab == "text"} id="tp-text">
              <form id="text-form" phx-change="title_changed" onsubmit="return false">
                <input
                  type="text"
                  class="ed-title"
                  id="edTitle"
                  name="title"
                  value={@article.title}
                  placeholder="Title"
                  aria-label="Title"
                  autocomplete="off"
                  phx-debounce="300"
                  readonly={!@holds_lock}
                  phx-click={!@holds_lock && "ask_takeover"}
                />
              </form>
              <div class={["relative", !@holds_lock && "is-readonly"]} id="bodyWrap">
                <div
                  id="edBodyHost"
                  class="ed-body ed-cm"
                  phx-hook="BodyEd"
                  phx-update="ignore"
                  data-readonly={to_string(!@holds_lock)}
                >
                  <textarea
                    class="ed-body"
                    aria-label="Body, Markdown"
                    spellcheck="false"
                    placeholder="Write. Markdown works: ## for a heading. Paste an image or drop one here to put it in the text."
                    readonly={!@holds_lock}
                  >{@article.body}</textarea>
                </div>
                <p class="ed-foot" id="edFoot">
                  <span class="flag">
                    <i class="inline-block w-[6px] h-[6px] rounded-full bg-accent"></i>Editing
                  </span>
                  <span id="edFootText">
                    <%= if @holds_lock do %>
                      Markdown. The draft saves as you type. <b>Save version</b>
                      keeps the title and the body as they stand, and the Versions tab shows what changed.
                    <% else %>
                      Markdown. The title and the body are read-only right now. <b>Save version</b>
                      and the Versions tab still work.
                    <% end %>
                  </span>
                </p>
              </div>
            </div>

            <div :if={@tab == "log"} id="tp-log">
              <p class="note mb-4">
                Everything that happened to this text, newest first: your edits, the edits of every other admin, every handover of the text, and every version anybody saved.
              </p>
              <div id="logList">
                <div :for={entry <- @log} class="log-row">
                  <time>{stamp(entry.inserted_at)}</time>
                  <span class={entry.user_id && entry.user_id != @current_scope.user.id && "j"}>
                    {log_line(entry)}
                  </span>
                </div>
              </div>
            </div>

            <div :if={@tab == "versions"} id="tp-versions">
              <p class="note mb-4">
                A version is the main text and nothing else: the title and the body. Article settings are never versioned, because they are shared and live.
                <b>Save version</b>
                in the bar writes one; every version below shows what changed against the one before it, and can be put back into the editor.
              </p>
              <div id="versionsList">
                <p :if={@versions == []} class="note">
                  No versions yet. <b>Save version</b>
                  in the bar writes the first one, and every one after it shows what changed.
                </p>
                <div
                  :for={{version, index} <- Enum.with_index(@versions)}
                  class="py-4 border-b border-hair"
                >
                  <div class="flex items-baseline gap-3 flex-wrap">
                    <b class="text-[13.5px] num">{stamp(version.inserted_at)}</b>
                    <span class={[
                      "text-[12.5px]",
                      if(version.user_id && version.user_id != @current_scope.user.id,
                        do: "text-julia font-semibold",
                        else: "text-dim"
                      )
                    ]}>
                      {author_name(version)}
                    </span>
                    <span class="note num">{word_count(version.body)} words</span>
                    <span :if={index == 0} class="note">newest</span>
                    <span class="sp"></span>
                    <button
                      class="btn quiet sm"
                      phx-click="restore_version"
                      phx-value-id={version.id}
                    >
                      Restore this version
                    </button>
                  </div>
                  <p class="note mt-[6px]">
                    <%= if index + 1 < length(@versions) do %>
                      What changed against the version from {stamp(
                        Enum.at(@versions, index + 1).inserted_at
                      )}: <span class="dif-add">added</span>, <span class="dif-del">removed</span>.
                    <% else %>
                      The first version of the text.
                    <% end %>
                  </p>
                  <div class="font-serif text-[15px] leading-[1.65] mt-2 whitespace-pre-wrap max-w-[62ch]">
                    <span
                      :for={{kind, text} <- diff_runs(@versions, index)}
                      class={diff_class(kind)}
                    >
                      {text}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <aside
          id="sideCol"
          aria-label="Article settings"
          class="quiet-fields lg:overflow-y-auto min-w-0 bg-paper border-t lg:border-t-0 lg:border-l border-rule px-[14px] lg:px-6 pt-[22px] pb-[100px] lg:pb-[110px]"
        >
          <%!-- article settings: Status first and merged with the date,
               then everything that describes the text. Nothing folded,
               and no Publish button: that one lives in the bar. The
               tiles block returns with the gallery. --%>
          <form id="artSettings" phx-change="settings_changed" onsubmit="return false">
            <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
              <span class="text-[13px] font-semibold">Article settings</span>
              <span class="sp"></span>
              <span class="note">Every change saves itself.</span>
            </div>

            <div class="drow pt-0.5">
              <span class="lab">Status</span>
              <span class="val">
                <div id="statusVal">
                  <span class="text-[14.5px]">{status_line(@article)}</span>
                  <div class="hint">{status_hint(@article)}</div>
                </div>
                <div class="mt-[11px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="edDate" id="edDateLab">
                    {if @article.status == "scheduled", do: "Goes live", else: "Publish date"}
                  </label>
                  <input
                    type="date"
                    id="edDate"
                    name="publish_date"
                    value={@article.publish_date}
                  />
                  <div class="hint" id="edDateHint">{date_hint(@article)}</div>
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">Type</span>
              <span class="val">
                <label class="opt">
                  <input
                    type="radio"
                    name="type"
                    value="post"
                    checked={@article.type == "post"}
                  />
                  <span>
                    Blog post<span class="note">Listed on the front page and in the feed, has tags, can email subscribers.</span>
                  </span>
                </label>
                <label class="opt">
                  <input
                    type="radio"
                    name="type"
                    value="page"
                    checked={@article.type == "page"}
                  />
                  <span>
                    Page<span class="note">Standalone, like About or Imprint. Appears in the site menu automatically, sorted by publish date, never in the feed.</span>
                  </span>
                </label>
              </span>
            </div>

            <div :if={@article.type != "page"} class="drow" id="fieldTags">
              <span class="lab">Tags</span>
              <span class="val">
                <input type="text" id="edTags" name="tags" value={@article.tags} phx-debounce="300" />
                <div class="hint">Comma separated; each tag becomes an archive page.</div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">Address</span>
              <span class="val">
                <span class="addr">
                  <span class="pre">{TexttileWeb.Endpoint.host()}/</span>
                  <input
                    type="text"
                    id="edSlug"
                    name="slug"
                    value={@article.slug}
                    spellcheck="false"
                    autocapitalize="off"
                    phx-debounce="300"
                  />
                </span>
                <div class="hint" id="slugHint">{slug_hint(@article)}</div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">Reading</span>
              <span class="val">
                <label class="opt">
                  <input type="hidden" name="allow_comments" value="false" />
                  <input
                    type="checkbox"
                    id="optComments"
                    name="allow_comments"
                    value="true"
                    checked={@article.allow_comments}
                  /> <span>Allow comments</span>
                </label>
                <label class="opt">
                  <input type="hidden" name="protected" value="false" />
                  <input
                    type="checkbox"
                    id="optProtected"
                    name="protected"
                    value="true"
                    checked={@article.protected}
                  />
                  <span>
                    Ask for the blog password first<span class="note">Readers need the site password; search engines see nothing.</span>
                  </span>
                </label>
              </span>
            </div>

            <div class="drow">
              <span class="lab">Subscribers</span>
              <span class="val" id="notifyOpt">
                <%= if @article.type == "page" do %>
                  <span class="note">Pages never email anyone.</span>
                <% else %>
                  <label class="opt">
                    <input type="hidden" name="notify_on_publish" value="false" />
                    <input
                      type="checkbox"
                      id="optNotify"
                      name="notify_on_publish"
                      value="true"
                      checked={@article.notify_on_publish}
                    />
                    <span>
                      Email subscribers<span class="note">{notify_note(@article)}</span>
                    </span>
                  </label>
                <% end %>
              </span>
            </div>
          </form>
        </aside>
      </div>

      <%!-- the one small dialog: delete, publish-anyway, the takeover --%>
      <div
        :if={@dialog}
        class="fixed inset-0 z-[80] grid place-items-center p-5"
        style="background: var(--tt-scrim)"
        id="scrim"
        phx-click="cancel_dialog"
        phx-window-keydown="cancel_dialog"
        phx-key="escape"
      >
        <div
          class="w-[min(430px,100%)] bg-paper px-[22px] pt-5 pb-[18px]"
          style="border-radius: var(--tt-radius-pop); border: 1px solid var(--tt-rule); box-shadow: 0 22px 54px rgb(var(--tt-shadow) / .26)"
          role="dialog"
          aria-modal="true"
          aria-labelledby="dlgH"
          id="dialog"
          phx-click-away="cancel_dialog"
        >
          <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em]" id="dlgH">
            {@dialog.title}
          </h2>
          <p
            :for={line <- @dialog.body}
            class="text-[13.5px] text-inksoft mt-[9px] leading-[1.55]"
          >
            {line}
          </p>
          <div class="flex gap-2 mt-[18px]">
            <button class="btn solid" id="dlgOk" phx-click={@dialog.event} autofocus>
              {@dialog.ok}
            </button>
            <button class="btn quiet" id="dlgNo" phx-click="cancel_dialog">Cancel</button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp chevron_icon(assigns) do
    ~H"""
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="m6 9 6 6 6-6" />
    </svg>
    """
  end

  ## Copy

  defp title_of(%{title: ""}), do: "Untitled"
  defp title_of(%{title: title}), do: title

  defp stamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp holder_name(%{user_id: user_id}) do
    Accounts.display_name(Accounts.get_user!(user_id))
  end

  defp author_name(%{user: nil}), do: "—"
  defp author_name(%{user: user}), do: Accounts.display_name(user)

  defp log_line(%{user: nil, text: text}), do: text
  defp log_line(%{user: user, text: text}), do: "#{Accounts.display_name(user)} #{text}"

  defp word_count(text) do
    case text |> to_string() |> String.split(~r/\s+/, trim: true) do
      [] -> 0
      words -> length(words)
    end
  end

  defp diff_runs(versions, index) do
    version = Enum.at(versions, index)
    previous = Enum.at(versions, index + 1) || %{title: "", body: ""}

    Articles.diff(
      previous.title <> "\n\n" <> previous.body,
      version.title <> "\n\n" <> version.body
    )
    |> Enum.chunk_by(fn {kind, _} -> kind end)
    |> Enum.map(fn chunk ->
      {kind, _} = hd(chunk)
      {kind, chunk |> Enum.map(fn {_, text} -> text end) |> Enum.join()}
    end)
  end

  defp diff_class(:add), do: "dif-add"
  defp diff_class(:del), do: "dif-del"
  defp diff_class(:same), do: nil

  defp will_notify?(article), do: article.type != "page" and article.notify_on_publish

  defp status_line(%{status: "draft"} = article),
    do: "Draft · last edited #{Calendar.strftime(article.updated_at, "%Y-%m-%d")}"

  defp status_line(%{status: "scheduled"} = article),
    do:
      "Scheduled · " <>
        if(article.publish_date, do: "goes live #{article.publish_date}", else: "no date yet")

  defp status_line(article), do: "Published #{article.publish_date}"

  defp status_hint(%{status: "draft"}),
    do: "Publish it with the button in the bar. It is a draft until then."

  defp status_hint(%{status: "scheduled"}),
    do: "Publish now or unschedule it with the button in the bar."

  defp status_hint(_article), do: "Unpublish it with the button in the bar."

  defp date_hint(%{status: "draft"}),
    do: "Empty means whenever you publish. A future date schedules the text."

  defp date_hint(%{status: "scheduled"} = article) do
    if article.publish_date,
      do: "Scheduled. The subscriber email goes out on #{article.publish_date}.",
      else: "Pick the day it goes live."
  end

  defp date_hint(article) do
    if article.publish_date,
      do: "Live since #{article.publish_date}. A future date puts it back in the queue.",
      else: "Pick the day it went live. An empty field makes the text a draft again."
  end

  defp slug_hint(%{status: "draft"}), do: "Free to change while the text is a draft."

  defp slug_hint(article) do
    "#{TexttileWeb.Endpoint.host()}/#{article.slug} is live; changing it breaks old links."
  end

  defp notify_note(%{status: "draft", notify_on_publish: true}),
    do:
      "Confirmed subscribers get one plain email with the title and the first paragraph when this goes live. Uncheck to publish silently."

  defp notify_note(%{status: "draft"}),
    do:
      "Nobody will be emailed when this goes live. Check it to notify the confirmed subscribers."

  defp notify_note(%{status: "scheduled", notify_on_publish: true} = article),
    do:
      "Goes out to the confirmed subscribers when the text goes live on #{article.publish_date}. Uncheck any time before then."

  defp notify_note(%{status: "scheduled"} = article),
    do: "No email will go out on #{article.publish_date}. Check it and it goes out at go-live."

  defp notify_note(_article),
    do: "No email went out for this text; sending one arrives with the newsletter."
end
