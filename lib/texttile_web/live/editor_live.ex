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
  alias Texttile.Gallery

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
      |> assign(:upload_pcts, %{})
      |> assign(:flush_pending, false)
      |> assign(:versions, Articles.versions(article))
      |> assign(:log, Articles.log(article))
      |> assign(:gallery, Gallery.list(article.id))
      |> assign(:gallery_rev, 0)

    socket =
      if connected?(socket) do
        Articles.subscribe(article.id)

        socket =
          case Lock.acquire(article.id, user.id, self()) do
            :ok -> assign(socket, :holds_lock, true)
            {:held, holder} -> socket |> assign(:holds_lock, false) |> assign(:holder, holder)
          end

        announce_activity(socket)
      else
        socket
      end

    {:ok, assign(socket, :page_title, Articles.display_title(article))}
  end

  # The wordmark menu and the other editor's banner read this: which
  # text this tab is in, and whether it writes or reads along.
  defp announce_activity(socket) do
    %{article: article, current_scope: scope, holds_lock: holds} = socket.assigns

    if connected?(socket) do
      TexttileWeb.Desk.update_activity(scope, %{
        text_id: article.id,
        text_title: Articles.display_title(article),
        writing: holds
      })
    end

    socket
  end

  # Release the lock only when the person deliberately leaves the
  # editor ({:shutdown, :left} is live navigation). A transport close -
  # a reload, a tab close, a network drop - stops the channel with
  # {:shutdown, :closed} instead and must fall through to the lock's
  # monitor, so the 45 s grace period can hand the lock back silently.
  def terminate({:shutdown, :left}, socket) do
    if socket.assigns[:article], do: Lock.release(socket.assigns.article.id, self())
    :ok
  end

  def terminate(_reason, _socket), do: :ok

  ## Events · the text

  # phx-change while typing, phx-submit when Enter is pressed: both save
  # the title. Without the submit binding, Enter would submit the form
  # the browser's way, reload the page, and throw away everything the
  # debounce had not sent yet.
  def handle_event("title_changed", %{"title" => title}, socket) do
    save_title(socket, title)
  end

  def handle_event("title_submitted", %{"title" => title}, socket) do
    save_title(socket, title)
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

  # The client's answer to flush_body: the keystrokes that were still
  # in its debounce when the takeover started.
  def handle_event("body_flushed", %{"text" => text}, socket) do
    socket =
      if socket.assigns.holds_lock and text != socket.assigns.article.body do
        {:ok, article} = Articles.update_text(socket.assigns.article, %{body: text})
        assign(socket, :article, article)
      else
        socket
      end

    {:noreply, finish_flush(socket)}
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
      when field in ~w(type tags slug allow_comments notify_on_publish) do
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
       title: ~s(Delete "#{Articles.display_title(article)}"?),
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
       ~s("#{Articles.display_title(article)}" is deleted. Its versions and its log went with it.)
     )
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  ## Events · images in the text. The files and the running requests
  ## live in the holder's browser; these events keep the Log and the
  ## panel's progress display current. Inserting into the body needs
  ## the lock, so every one of these does too, and a file name is
  ## client text: it gets a short leash before it reaches the Log.

  def handle_event(
        "images_inserted",
        %{"files" => names},
        %{assigns: %{holds_lock: true}} = socket
      )
      when is_list(names) do
    %{article: article, current_scope: scope} = socket.assigns

    Articles.push_log(
      article,
      scope.user,
      case names do
        [one] -> "put #{clean_file(one)} into the text"
        many -> "put #{length(many)} images into the text"
      end
    )

    {:noreply, socket}
  end

  def handle_event("images_inserted", _params, socket), do: {:noreply, socket}

  def handle_event("upload_progress", %{"file" => file, "pct" => pct}, socket)
      when is_number(pct) do
    {:noreply,
     assign(socket, :upload_pcts, Map.put(socket.assigns.upload_pcts, clean_file(file), pct))}
  end

  def handle_event("image_uploaded", %{"file" => file}, %{assigns: %{holds_lock: true}} = socket) do
    %{article: article, current_scope: scope} = socket.assigns
    file = clean_file(file)
    Articles.push_log(article, scope.user, "#{file} is in the text")
    {:noreply, assign(socket, :upload_pcts, Map.delete(socket.assigns.upload_pcts, file))}
  end

  def handle_event("image_uploaded", _params, socket), do: {:noreply, socket}

  def handle_event(
        "image_failed",
        %{"file" => file, "pct" => pct},
        %{assigns: %{holds_lock: true}} = socket
      )
      when is_number(pct) do
    %{article: article, current_scope: scope} = socket.assigns
    file = clean_file(file)
    Articles.push_log(article, scope.user, "#{file} failed to upload into the text")

    {:noreply,
     socket
     |> assign(:upload_pcts, Map.put(socket.assigns.upload_pcts, file, pct))
     |> mark_saved("#{file} failed at #{round(pct)}% · retry or remove it under the text")}
  end

  def handle_event("image_failed", _params, socket), do: {:noreply, socket}

  def handle_event("image_retry", %{"file" => file}, %{assigns: %{holds_lock: true}} = socket) do
    %{article: article, current_scope: scope} = socket.assigns
    file = clean_file(file)
    Articles.push_log(article, scope.user, "retried the upload of #{file}")
    {:noreply, assign(socket, :upload_pcts, Map.put(socket.assigns.upload_pcts, file, 0))}
  end

  def handle_event("image_retry", _params, socket), do: {:noreply, socket}

  def handle_event("image_retry_missing", %{"file" => file}, socket) do
    {:noreply,
     mark_saved(
       socket,
       "The file for #{clean_file(file)} is not in this browser any more · remove the marker and paste the image again"
     )}
  end

  def handle_event(
        "image_removed",
        %{"file" => file, "how" => how},
        %{assigns: %{holds_lock: true}} = socket
      ) do
    %{article: article, current_scope: scope} = socket.assigns
    file = clean_file(file)

    Articles.push_log(
      article,
      scope.user,
      if(how == "cancel",
        do: "cancelled the upload of #{file}",
        else: "took the marker for #{file} out of the text"
      )
    )

    {:noreply, assign(socket, :upload_pcts, Map.delete(socket.assigns.upload_pcts, file))}
  end

  def handle_event("image_removed", _params, socket), do: {:noreply, socket}

  ## Events · the gallery
  #
  # Deliberately not guarded by the lock: the gallery is the
  # conflict-poor half of the editor and stays open to every admin at
  # once. Ids arrive as client strings and are parsed, never trusted.

  def handle_event("gallery_reorder", %{"id" => id, "ids" => ids}, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, ids} <- parse_ids(ids),
         {:ok, image} <- Gallery.reorder(article.id, id, ids, by: scope.user.id) do
      Articles.push_log(article, scope.user, "moved #{image.filename} in the gallery")
      {:noreply, socket |> assign_gallery() |> mark_saved()}
    else
      _ ->
        {:noreply,
         socket
         |> assign_gallery()
         |> mark_saved("The gallery changed under your hands · fresh order loaded")}
    end
  end

  def handle_event("gallery_set_date", %{"id" => id, "date" => date}, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, image} <- Gallery.set_date(article.id, id, date, by: scope.user.id) do
      Articles.push_log(
        article,
        scope.user,
        "set the date of #{image.filename} to #{Calendar.strftime(image.gallery_date, "%Y-%m-%d %H:%M")}"
      )

      {:reply, %{ok: true}, socket |> assign_gallery() |> mark_saved()}
    else
      {:error, :invalid_date} ->
        {:reply, %{ok: false}, mark_saved(socket, "That date could not be read")}

      _ ->
        {:reply, %{ok: false}, socket |> assign_gallery() |> mark_saved(gone_note())}
    end
  end

  def handle_event("gallery_set_meta", %{"id" => id} = params, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, _image} <-
           Gallery.set_meta(article.id, id, Map.take(params, ["alt", "caption"]),
             by: scope.user.id
           ) do
      {:reply, %{ok: true}, socket |> assign_gallery() |> mark_saved()}
    else
      _ -> {:reply, %{ok: false}, socket |> assign_gallery() |> mark_saved(gone_note())}
    end
  end

  def handle_event("gallery_delete", %{"id" => id}, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, image} <- Gallery.delete(article.id, id, by: scope.user.id) do
      Articles.push_log(article, scope.user, "took #{image.filename} out of the gallery")
      {:noreply, socket |> assign_gallery() |> mark_saved()}
    else
      _ -> {:noreply, socket |> assign_gallery() |> mark_saved(gone_note())}
    end
  end

  def handle_event("gallery_undo", %{"id" => id}, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, image} <- Gallery.undo(article.id, id, by: scope.user.id) do
      Articles.push_log(article, scope.user, "put #{image.filename} back")

      {:noreply,
       socket |> assign_gallery() |> mark_saved("#{image.filename} is back in the gallery")}
    else
      _ ->
        {:noreply, mark_saved(socket, "Too late · the picture is gone for good")}
    end
  end

  # The client's ask to reconcile after a drag. While a tile was held,
  # patches to the grid were skipped; bumping the rev changes every
  # tile's render, so the next patch carries the whole grid and the
  # DOM matches the server again whatever was missed.
  def handle_event("gallery_refresh", _params, socket) do
    {:noreply,
     socket
     |> assign_gallery()
     |> assign(:gallery_rev, socket.assigns.gallery_rev + 1)}
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {id, ""} -> {:ok, id}
      _ -> {:error, :bad_id}
    end
  end

  defp parse_ids(ids) when is_list(ids) do
    parsed = Enum.map(ids, &parse_id/1)

    if Enum.all?(parsed, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed, fn {:ok, id} -> id end)}
    else
      {:error, :bad_id}
    end
  end

  defp parse_ids(_ids), do: {:error, :bad_id}

  defp assign_gallery(socket) do
    assign(socket, :gallery, Gallery.list(socket.assigns.article.id))
  end

  defp gone_note, do: "That picture was deleted a moment ago"

  defp moved_note(socket, meta) do
    name =
      case Accounts.get_user(meta.by) do
        nil -> "Someone"
        user -> Accounts.display_name(user)
      end

    file =
      case Enum.find(socket.assigns.gallery, &(&1.id == meta.image_id)) do
        nil -> "a picture"
        image -> image.filename
      end

    "#{name} moved #{file}."
  end

  defp do_publish(socket, opts) do
    %{article: article, current_scope: scope} = socket.assigns

    case Articles.publish(article, scope.user, opts) do
      {:ok, article} -> publish_done(socket, article)
      {:error, _changeset} -> mark_saved(socket, "That address is taken by another text")
    end
  end

  defp publish_done(socket, article) do
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

  # a file name is client text before it reaches the Log
  defp clean_file(file), do: file |> to_string() |> String.slice(0, 120)

  defp save_title(socket, title) do
    cond do
      not socket.assigns.holds_lock ->
        {:noreply, socket}

      true ->
        case Articles.update_text(socket.assigns.article, %{title: title}) do
          {:ok, article} ->
            Lock.ping(article.id, self())
            {:noreply, socket |> assign(:article, article) |> announce_activity() |> mark_saved()}

          {:error, _changeset} ->
            {:noreply, mark_saved(socket, "That title is too long; 500 characters is the roof")}
        end
    end
  end

  # a thumbnail loads the scaled reading, never the full original
  defp thumb_url("/uploads/" <> relative), do: "/desk/renditions/320/" <> relative
  defp thumb_url(url), do: String.replace(url, "'", "%27")

  defp tile_count(gallery) do
    case length(gallery) do
      1 -> "1 image"
      n -> "#{n} images"
    end
  end

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

  # Every gallery change, own or foreign, lands here: the list is
  # re-read once. When somebody else sorted, the moved tile gets its
  # moment of color and the note under the grid says who.
  def handle_info({:gallery_changed, id, meta}, socket) do
    cond do
      id != socket.assigns.article.id ->
        {:noreply, socket}

      meta.action == :reordered and meta.by != nil and
          meta.by != socket.assigns.current_scope.user.id ->
        {:noreply,
         socket
         |> assign_gallery()
         |> push_event("gallery_moved", %{id: meta.image_id, note: moved_note(socket, meta)})}

      true ->
        {:noreply, assign_gallery(socket)}
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

  # The lock asks this holder to flush before a takeover: first the
  # client hands over what still sits in its debounce, then a version
  # snapshot, only then the transfer. A client that does not answer
  # within the fallback window is not waited for; the last autosaved
  # state stands in.
  def handle_info({:lock_flush, id}, socket) do
    if id == socket.assigns.article.id do
      Process.send_after(self(), :flush_fallback, 700)
      {:noreply, socket |> assign(:flush_pending, true) |> push_event("flush_body", %{})}
    else
      Lock.flushed(id)
      {:noreply, socket}
    end
  end

  def handle_info(:flush_fallback, socket) do
    if socket.assigns[:flush_pending] do
      {:noreply, finish_flush(socket)}
    else
      {:noreply, socket}
    end
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
          %{user_id: user_id} -> Accounts.get_user(user_id)
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

  # Autosave settled, snapshot written, transfer free to go ahead.
  defp finish_flush(socket) do
    %{article: article, current_scope: scope} = socket.assigns

    if socket.assigns[:flush_pending] do
      Articles.snapshot(article, scope.user)
      Lock.flushed(article.id)
    end

    assign(socket, :flush_pending, false)
  end

  defp refresh_lock(socket) do
    article = socket.assigns.article

    {holds, holder} =
      case Lock.state(article.id) do
        :free ->
          # A free lock goes to whoever has the text open - except to
          # the tab that was just released for being idle: taking it
          # straight back would undo the release, forever. That tab
          # turns read-only and gets the lock again the moment its
          # person actually touches the text.
          if socket.assigns.holds_lock do
            {false, nil}
          else
            case Lock.acquire(article.id, socket.assigns.current_scope.user.id, self()) do
              :ok -> {true, nil}
              {:held, holder} -> {false, holder}
            end
          end

        %{pid: pid} = holder ->
          {pid == self(), holder}
      end

    socket
    |> assign(:holds_lock, holds)
    |> assign(:holder, unless(holds, do: holder))
    |> push_event("set_readonly", %{readOnly: !holds})
    |> announce_activity()
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
      crumb={Articles.display_title(@article)}
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
              :if={
                (!@holds_lock && @holder) || (@holds_lock && reading_along(@others, @article) != [])
              }
              class={[
                "flex items-baseline gap-[9px] flex-wrap rounded-[5px] px-[13px] py-2 text-[13px] mb-5",
                if(@holds_lock, do: "bg-accentwash text-accent", else: "bg-livetint text-livetext")
              ]}
              id="jbar"
              style={"box-shadow: inset 0 0 0 1px var(--tt-#{if @holds_lock, do: "accentline", else: "liveline"})"}
            >
              <span class="flex items-center gap-[9px] flex-none">
                <span class="dot live text-julia"></span>
                <b class="text-julia">
                  {if @holds_lock,
                    do: Enum.join(reading_along(@others, @article), ", "),
                    else: holder_name(@holder)}
                </b>
              </span>
              <span class="opacity-85 flex-1 min-w-[220px]">
                <%= if @holds_lock do %>
                  reads along while you write. The article settings stay open to every admin, at the same time.
                <% else %>
                  writes the text now, and you see every word arrive. Click into the title or the body to take the text over. The article settings stay open to every admin, at the same time.
                <% end %>
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
              <form id="text-form" phx-change="title_changed" phx-submit="title_submitted">
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
              <%!-- the formatting bar: nine quiet buttons for the admin
                   who does not know Markdown, and a hint for the one who
                   does. Every button writes plain Markdown through the
                   same commands the keyboard uses; the hook swallows the
                   mousedown so the caret never leaves the text. --%>
              <div
                class={["mdbar", !@holds_lock && "is-readonly"]}
                id="mdBar"
                role="toolbar"
                aria-label="Formatting"
              >
                <button
                  type="button"
                  class="mdb"
                  data-cmd="heading"
                  title="Heading. Click again for the next size."
                  aria-label="Heading"
                >
                  <span class="g font-serif font-semibold text-[15px]">H</span>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="bold"
                  title="Bold (Ctrl or Cmd + B)"
                  aria-label="Bold"
                >
                  <span class="g font-serif font-bold text-[14.5px]">B</span>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="italic"
                  title="Italic (Ctrl or Cmd + I)"
                  aria-label="Italic"
                >
                  <span class="g font-serif italic font-semibold text-[14.5px]">I</span>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="link"
                  title="Link (Ctrl or Cmd + K)"
                  aria-label="Link"
                >
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                  >
                    <path d="M6.5 9.5 9.5 6.5" />
                    <path d="M7.2 4.6l1.5-1.5a2.6 2.6 0 0 1 3.7 3.7l-1.5 1.5" />
                    <path d="M8.8 11.4l-1.5 1.5a2.6 2.6 0 0 1-3.7-3.7l1.5-1.5" />
                  </svg>
                </button>
                <span class="mdsep" aria-hidden="true"></span>
                <button type="button" class="mdb" data-cmd="quote" title="Quote" aria-label="Quote">
                  <span class="g font-serif font-bold text-[17px] leading-none pt-[5px]">
                    &rdquo;
                  </span>
                </button>
                <button type="button" class="mdb" data-cmd="bullet" title="List" aria-label="List">
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                  >
                    <circle cx="3" cy="4" r=".4" fill="currentColor" />
                    <circle cx="3" cy="8" r=".4" fill="currentColor" />
                    <circle cx="3" cy="12" r=".4" fill="currentColor" />
                    <path d="M6.5 4h6.5M6.5 8h6.5M6.5 12h6.5" />
                  </svg>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="ordered"
                  title="Numbered list"
                  aria-label="Numbered list"
                >
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                  >
                    <path d="M7.5 4h5.5M7.5 8h5.5M7.5 12h5.5" />
                    <text
                      x="1.6"
                      y="6"
                      font-size="6.5"
                      fill="currentColor"
                      stroke="none"
                      font-family="inherit"
                    >
                      1
                    </text>
                    <text
                      x="1.6"
                      y="14"
                      font-size="6.5"
                      fill="currentColor"
                      stroke="none"
                      font-family="inherit"
                    >
                      2
                    </text>
                  </svg>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="task"
                  title="Task list. Click a box in the text to tick it."
                  aria-label="Task list"
                >
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <rect x="2.2" y="2.2" width="11.6" height="11.6" rx="2.6" />
                    <path d="M5.2 8.2l2 2 3.6-4" />
                  </svg>
                </button>
                <span class="mdsep" aria-hidden="true"></span>
                <button type="button" class="mdb" data-cmd="code" title="Code" aria-label="Code">
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M6 4.5 2.5 8 6 11.5" />
                    <path d="M10 4.5 13.5 8 10 11.5" />
                  </svg>
                </button>
                <button
                  type="button"
                  class="mdb"
                  data-cmd="image"
                  title="Put an image in the text, at the caret"
                  aria-label="Image"
                >
                  <svg
                    class="g"
                    viewBox="0 0 16 16"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.6"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <rect x="2.2" y="3.2" width="11.6" height="9.6" rx="1.6" />
                    <circle cx="5.6" cy="6.4" r="1" />
                    <path d="M2.6 11.4 6.5 8l3 2.6 1.9-1.6 2.2 2" />
                  </svg>
                </button>
                <span class="sp"></span>
                <span class="note hidden sm:inline self-center">Markdown works too.</span>
              </div>
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
                <span class="drop-flag" id="bodyDropFlag" hidden>
                  Put the image in the text, where the caret is
                </span>
              </div>
              <input
                type="file"
                id="mdImgFile"
                class="sr"
                multiple
                accept="image/*"
                aria-label="Put images in the text"
              />

              <%!-- the images in the text: a reading of the body, never
                   a list of its own. An upload that is still running
                   holds its place with a token, and the token becomes
                   the reference when the upload finishes. --%>
              <div class="mt-[34px]">
                <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
                  <span class="text-[13px] font-semibold">
                    Images in the text
                    <span class="note num" id="inlineCount">{inline_count(@article.body)}</span>
                  </span>
                  <span class="sp"></span>
                  <span class="note">Paste one into the text, or drop one on it.</span>
                </div>
                <div id="inlineImgs">
                  <p :if={Articles.inline_refs(@article.body) == []} class="note pt-[10px]">
                    None in this text yet. Paste an image into the text, or drop one on it.
                  </p>
                  <%= for ref <- Articles.inline_refs(@article.body) do %>
                    <div
                      :if={ref.kind == :done}
                      class="flex items-center gap-[11px] py-[9px] border-b border-hair text-[13px]"
                    >
                      <span
                        class="w-9 h-9 r-img bg-field bg-center bg-cover flex-none"
                        style={"background-image:url('#{thumb_url(ref.url)}')"}
                      >
                      </span>
                      <span class="font-semibold flex-none">{ref.file}</span>
                      <span class="sp"></span>
                      <span class="text-faint text-[12px] break-words">{ref.raw}</span>
                    </div>
                    <div :if={ref.kind == :failed} class="py-[9px] border-b border-hair text-[13px]">
                      <div class="flex items-center gap-[11px] flex-wrap">
                        <span class="w-9 h-9 r-img bg-field flex-none"></span>
                        <span class="font-semibold flex-none text-julia">{ref.file}</span>
                        <span class="sp"></span>
                        <%= if @holds_lock do %>
                          <button class="btn sm" data-img-action="retry" data-img-file={ref.file}>
                            Retry
                          </button>
                          <button class="btn sm" data-img-action="remove" data-img-file={ref.file}>
                            Remove
                          </button>
                        <% end %>
                      </div>
                      <p class="note mt-[5px] max-w-[62ch]">
                        The upload stopped at {@upload_pcts[ref.file] || 0}%, so the file never reached the server. The text keeps a marker where the image belongs. Retry sends the same file again. Remove takes the marker out of the text.
                      </p>
                    </div>
                    <div :if={ref.kind == :running} class="py-[9px] border-b border-hair text-[13px]">
                      <div class="flex items-center gap-[11px] flex-wrap">
                        <span class="w-9 h-9 r-img bg-field flex-none"></span>
                        <span class="font-semibold flex-none">{ref.file}</span>
                        <span class="note num">
                          {if (@upload_pcts[ref.file] || 0) == 0,
                            do: "queued",
                            else: "uploading #{@upload_pcts[ref.file]}%"}
                        </span>
                        <span class="sp"></span>
                        <button
                          :if={@holds_lock}
                          class="btn sm"
                          data-img-action="cancel"
                          data-img-file={ref.file}
                        >
                          Cancel
                        </button>
                      </div>
                      <span class="track mt-[7px]">
                        <i style={"width:#{@upload_pcts[ref.file] || 0}%"}></i>
                      </span>
                      <p class="note mt-[5px]">
                        The text holds the place. The marker becomes the image when the upload finishes.
                      </p>
                    </div>
                  <% end %>
                </div>
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
                  class="py-[22px] border-t-2 border-rule first:border-t-0"
                >
                  <div class="flex items-baseline gap-3 flex-wrap">
                    <span class="font-serif text-[18px] font-semibold tracking-[-.01em] num">
                      {stamp(version.inserted_at)}
                    </span>
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
                  <%!-- pre-wrap renders template whitespace, so the marked
                       spans must stay glued to their text --%>
                  <div
                    class="font-serif text-[15px] leading-[1.65] mt-2 whitespace-pre-wrap max-w-[62ch]"
                    phx-no-format
                  ><span :for={{kind, text} <- diff_runs(@versions, index)} class={diff_class(kind)}>{text}</span></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <aside
          id="sideCol"
          aria-label="Article settings"
          class="lg:overflow-y-auto min-w-0 bg-paper border-t lg:border-t-0 lg:border-l border-rule px-[14px] lg:px-6 pt-[22px] pb-[100px] lg:pb-[110px]"
        >
          <%!-- The tiles block: the gallery as the reader will see it.
               Server truth renders into #tileServer; the hook owns the
               local upload tiles (#tileLocal), the drag, the lightbox
               and the undo bar. display:contents lets both halves
               share one grid. --%>
          <div
            id="tilesBlock"
            class="relative"
            phx-hook="Gallery"
            data-article-id={@article.id}
            data-upload-url={~p"/desk/texts/#{@article.id}/gallery"}
            data-csrf={Phoenix.Controller.get_csrf_token()}
          >
            <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
              <span class="text-[13px] font-semibold">
                Tiles <span class="note num" id="tileCount">{tile_count(@gallery)}</span>
                <span class="note num" id="tileOnWay" phx-update="ignore"></span>
              </span>
              <span class="sp"></span>
              <span class="note">The order is the gallery.</span>
            </div>
            <div class="grid gap-[6px] grid-cols-3 lg:grid-cols-2 xl:grid-cols-3 mt-3" id="tileGrid">
              <div class="contents" id="tileServer">
                <div
                  :for={{image, index} <- Enum.with_index(@gallery, 1)}
                  class="tile"
                  id={"tile-#{image.id}"}
                  data-id={image.id}
                  data-rev={@gallery_rev}
                  data-filename={image.filename}
                  data-date={Calendar.strftime(image.gallery_date, "%Y-%m-%dT%H:%M")}
                  data-alt={image.alt}
                  data-caption={image.caption}
                  data-full={"/desk/renditions/max/" <> image.path}
                  data-original={"/uploads/" <> image.path}
                  title={"#{image.filename} · #{Calendar.strftime(image.gallery_date, "%Y-%m-%d")}"}
                  style={"background-image:url('/desk/renditions/320/#{image.path}')"}
                  role="button"
                  tabindex="0"
                  aria-label={"Image #{index}, #{image.filename}, grab to sort, tap to see it big"}
                >
                  <span class="n">{String.pad_leading("#{index}", 2, "0")}</span>
                </div>
              </div>
              <div class="contents" id="tileLocal" phx-update="ignore"></div>
              <button
                type="button"
                class="tile-add"
                id="tileAdd"
                aria-label="Add images"
              >
                + Add
              </button>
            </div>
            <input
              type="file"
              id="tileFiles"
              class="sr"
              multiple
              accept="image/*"
              aria-label="Add images to the gallery"
            />
            <span class="drop-flag" id="tileDropFlag" hidden>
              Add the image to the gallery, at the end
            </span>
            <p class="note mt-[10px] transition-colors" id="tileNote">
              Grab an image to sort it. Tap one to see it big.
            </p>
          </div>

          <%!-- article settings: Status first and merged with the date,
               then everything that describes the text. Nothing folded,
               and no Publish button: that one lives in the bar. --%>
          <form
            id="artSettings"
            class="mt-[34px]"
            phx-change="settings_changed"
            phx-submit="settings_changed"
          >
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
              <span class="lab">Readers</span>
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
                <span id="notifyOpt">
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

  defp stamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  # The account behind the lock may have been deleted while it held
  # the text; the banner still needs a word for the person.
  defp holder_name(%{user_id: user_id}) do
    case Accounts.get_user(user_id) do
      nil -> "A deleted account"
      user -> Accounts.display_name(user)
    end
  end

  defp author_name(%{user: nil}), do: "—"
  defp author_name(%{user: user}), do: Accounts.display_name(user)

  defp log_line(%{user: nil, text: text}), do: text
  defp log_line(%{user: user, text: text}), do: "#{Accounts.display_name(user)} #{text}"

  # Who else has this text open right now, by name; read from the desk
  # presence the wordmark menu already carries.
  defp reading_along(others, article) do
    for person <- others,
        Enum.any?(person.sessions, &(&1.text_id == article.id)),
        uniq: true,
        do: person.name
  end

  defp inline_count(body) do
    refs = Articles.inline_refs(body)
    done = Enum.count(refs, &(&1.kind == :done))
    running = Enum.count(refs, &(&1.kind == :running))
    failed = Enum.count(refs, &(&1.kind == :failed))

    "#{done} #{if done == 1, do: "image", else: "images"}" <>
      if(running > 0, do: " · #{running} on the way", else: "") <>
      if(failed > 0, do: " · #{failed} failed", else: "")
  end

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
    |> Enum.flat_map(fn
      {:same, text} ->
        [{:same, text}]

      {kind, text} ->
        # a mark across a line break draws as a floating coloured bar
        # over empty space, so a marked run breaks at its newlines and
        # the whitespace between goes unmarked (removed whitespace
        # vanishes; it has nowhere to stand)
        text
        |> String.split(~r/\n+/, include_captures: true, trim: true)
        |> Enum.flat_map(fn segment ->
          cond do
            String.trim(segment) != "" -> [{kind, segment}]
            kind == :add -> [{:same, segment}]
            true -> []
          end
        end)
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
