defmodule TexttileWeb.EditorLive do
  @moduledoc """
  One open text: the round-14 editor. The writing surface in the middle
  column with the Text, Comments, Log and Versions tabs; the article
  settings in the side column. The tiles block returns with the gallery.

  The title and the body belong to whoever holds the soft lock
  (`Texttile.Articles.Lock`); the article settings and the publish
  controls stay open to every admin all the time.
  """
  use TexttileWeb, :live_view

  import TexttileWeb.CommentComponents

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Articles.Lock
  alias Texttile.Comments
  alias Texttile.Gallery
  alias Texttile.Videos

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
      |> assign(:save_label, "Save version")
      |> assign(:save_timer, nil)
      |> assign(:holds_lock, true)
      |> assign(:holder, nil)
      |> assign(:upload_pcts, %{})
      |> assign(:flush_pending, false)
      |> assign(:versions, Articles.versions(article))
      |> assign(:log, Articles.log(article))
      |> assign(:redirects, Articles.redirects(article))
      |> assign(:gallery, Gallery.list(article.id))
      |> assign(:gallery_rev, 0)
      |> assign(:media_rev, 0)
      |> assign(:comments, Comments.for_article(article.id))
      |> assign(:cmt_require, Texttile.Settings.get(:comments_require_confirmation))
      |> assign(:editing_comment, nil)
      |> assign(:comment_error, nil)
      |> known_tags()

    # What the writing surface was told last. It reads the element on
    # its way in, so at the start the two agree.
    socket = assign(socket, :pushed_posters, poster_map(media(socket.assigns)))

    socket =
      if connected?(socket) do
        Articles.subscribe(article.id)
        Comments.subscribe()
        Texttile.Settings.subscribe()
        Videos.subscribe()

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

  # The Comments overview jumps straight into a text's Comments tab;
  # the address may name any tab.
  def handle_params(%{"tab" => tab}, _uri, socket)
      when tab in ~w(text comments log versions) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # The wordmark menu and the other editor's banner read this: which
  # text this tab is in, and whether it writes or reads along.
  defp announce_activity(socket) do
    %{article: article, current_scope: scope, holds_lock: holds} = socket.assigns

    if connected?(socket) do
      TexttileWeb.Admin.update_activity(scope, %{
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

      # A video pasted a moment ago reaches the server with this text
      # and may be converted already; its poster goes back with the
      # answer, because the conversion's own word came too early to
      # find the reference here.
      {:noreply, socket |> assign(:article, article) |> sync_posters() |> mark_saved()}
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

  # The button answers for itself. A version is not a save of the text -
  # the text saved itself while it was typed - so the news belongs on
  # the control that was pressed, not on the Last-saved line beside it.
  def handle_event("save_version", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    case Articles.save_version(article, scope.user) do
      {:ok, _version} -> {:noreply, socket |> mark_saved() |> say_on_button("Saved")}
      :unchanged -> {:noreply, say_on_button(socket, "Nothing changed")}
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

    {:noreply,
     socket
     |> assign(:article, article)
     |> reload_history()
     |> load_redirects()
     |> mark_saved(note)}
  end

  def handle_event("settings_changed", %{"_target" => [field | _]} = params, socket)
      when field in ~w(type tags slug allow_comments notify_on_publish) do
    %{article: article} = socket.assigns

    case Articles.update_settings(article, Map.take(params, [field])) do
      {:ok, article} ->
        socket = assign(socket, :article, article)
        socket = if field == "tags", do: known_tags(socket), else: socket
        {:noreply, socket |> load_redirects() |> mark_saved()}

      {:error, changeset} ->
        {:noreply, mark_saved(socket, slug_error(changeset))}
    end
  end

  def handle_event("settings_changed", _params, socket), do: {:noreply, socket}

  # The Reset beside the date label: the same thing as emptying the
  # field, which a date input makes hard by hand.
  def handle_event("clear_publish_date", _params, socket) do
    handle_event(
      "settings_changed",
      %{"_target" => ["publish_date"], "publish_date" => ""},
      socket
    )
  end

  # One old address off the list. The entry keeps every other one; from
  # now on that address is a 404 like any other.
  def handle_event("delete_redirect", %{"id" => id}, socket) do
    %{article: article} = socket.assigns

    with {id, ""} <- Integer.parse(to_string(id)) do
      :ok = Articles.delete_redirect(article, id)
    end

    {:noreply, socket |> load_redirects() |> mark_saved("That address answers nothing again")}
  end

  # The tag suggestions: one click adds a tag the blog already knows,
  # one more takes it off again. The field keeps the spelling it has;
  # only the tag being toggled comes and goes.
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    %{article: article} = socket.assigns
    tag = tag |> to_string() |> String.trim() |> String.downcase()

    written =
      article.tags
      |> to_string()
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    kept = Enum.reject(written, &(String.downcase(&1) == tag))
    tags = if kept == written, do: written ++ [tag], else: kept

    case Articles.update_settings(article, %{tags: Enum.join(tags, ", ")}) do
      {:ok, article} ->
        {:noreply, socket |> assign(:article, article) |> known_tags() |> mark_saved()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  ## Events · chrome

  def handle_event("set_tab", %{"tab" => tab}, socket)
      when tab in ~w(text comments log versions) do
    {:noreply, assign(socket, :tab, tab)}
  end

  # Only the open text's own comments, and a comment that is already
  # gone is no error: the list reloads either way. The trash itself
  # lives on the Comments screen; a text only ever deletes into it.
  def handle_event("delete_comment", %{"id" => id}, socket) do
    case own_comment(socket, id, & &1) do
      {:error, :gone} -> {:noreply, reload_comments(socket)}
      comment -> {:noreply, assign(socket, :dialog, delete_dialog(comment))}
    end
  end

  def handle_event("confirm_delete_comment", %{"id" => id}, socket) do
    own_comment(socket, id, &Comments.delete_comment(&1.id))

    {:noreply,
     socket
     |> assign(:dialog, nil)
     |> close_comment_edit()
     |> reload_comments()}
  end

  def handle_event("release_comment", %{"id" => id}, socket) do
    own_comment(socket, id, &Comments.release_comment(&1.id))
    {:noreply, reload_comments(socket)}
  end

  def handle_event("start_edit", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:editing_comment, to_string(id)) |> assign(:comment_error, nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, close_comment_edit(socket)}
  end

  def handle_event("save_comment", %{"comment_id" => id, "body" => body}, socket) do
    case own_comment(socket, id, &Comments.edit_comment(&1.id, body)) do
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :comment_error, edit_error(changeset))}

      _ ->
        {:noreply, socket |> close_comment_edit() |> reload_comments()}
    end
  end

  def handle_event("toggle_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, !socket.assigns.state_menu)}
  end

  def handle_event("close_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, false)}
  end

  def handle_event("ask_delete", _params, socket) do
    article = socket.assigns.article

    live_line =
      if article.status == "published" do
        address = TexttileWeb.Endpoint.host() <> Articles.public_path(article)

        [
          "The text is live. From now on, a reader who follows an old link to #{address} gets a 404 page."
        ]
      else
        []
      end

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
     |> push_navigate(to: ~p"/admin/texts")}
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

  # The preview picker in the article settings: a click chooses, a
  # second click on the chosen one lets the first image speak again.
  # Open to every admin, like the rest of the settings.
  def handle_event("set_preview", %{"path" => path}, socket) do
    %{article: article, gallery: gallery, current_scope: scope} = socket.assigns

    cond do
      path not in Gallery.preview_candidates(article, Enum.map(gallery, & &1.path)) ->
        {:noreply, socket |> assign_gallery() |> mark_saved(gone_note())}

      article.preview_path == path ->
        {:ok, article} = Articles.update_settings(article, %{preview_path: nil})
        {:noreply, socket |> assign(:article, article) |> mark_saved()}

      true ->
        {:ok, article} = Articles.update_settings(article, %{preview_path: path})
        Articles.push_log(article, scope.user, "chose #{Path.basename(path)} as the preview")
        {:noreply, socket |> assign(:article, article) |> mark_saved()}
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

  defp gone_note, do: "That tile was deleted a moment ago"

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
        "Published just now" <> published_mail_note(socket.assigns.article, article)
      end

    socket
    |> assign(:article, article)
    |> assign(:state_menu, false)
    |> reload_history()
    |> mark_saved(note)
  end

  # What the publish click owes the writer: whether the email left. The
  # stamp appearing on the text is the send; a text that carried one
  # already went out at an earlier go-live and stays quiet.
  defp published_mail_note(before, article) do
    cond do
      not will_notify?(article) ->
        ", quietly · no email sent"

      is_nil(before.notified_on) and not is_nil(article.notified_on) ->
        case Texttile.Newsletter.confirmed_count() do
          0 -> " · nobody is on the newsletter list, so no email went out"
          1 -> " · the email is on its way to 1 subscriber"
          n -> " · the email is on its way to #{n} subscribers"
        end

      true ->
        " · the subscribers already got this email"
    end
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
  defp thumb_url("/uploads/" <> relative), do: "/renditions/320/" <> relative
  defp thumb_url(url), do: String.replace(url, "'", "%27")

  # What every video of this text shows and how far it is, in one
  # query: the tiles of the gallery and the references in the words.
  defp media(%{article: article, gallery: gallery}) do
    inline =
      article.body
      |> Articles.inline_refs()
      |> Enum.flat_map(fn
        %{kind: :done, url: "/uploads/" <> relative} -> [relative]
        _ -> []
      end)

    (Enum.map(gallery, & &1.path) ++ inline)
    |> Enum.uniq()
    |> Videos.stills()
  end

  # The entry behind a reference in the words, whose url carries the
  # /uploads/ prefix the body writes.
  defp ref_media(media, "/uploads/" <> relative), do: media[relative]
  defp ref_media(_media, _url), do: nil

  # Hands the writing surface its posters, and only when they are not
  # the ones it already has: this runs on every body change, and a
  # text without a video has nothing to say every time.
  defp sync_posters(socket) do
    posters = poster_map(media(socket.assigns))

    if posters == socket.assigns.pushed_posters do
      socket
    else
      socket
      |> assign(:pushed_posters, posters)
      |> push_event("sync_media", %{posters: posters})
    end
  end

  # The poster of every converted video, for the writing surface: it
  # draws the markdown references, so it is told the body's own urls.
  # A video ffmpeg has not finished is absent and stays a play mark.
  # What the writing surface knows about the films in the words: the
  # poster behind the thumbnail, the poster the lightbox stands behind
  # the film, and the film itself. A conversion that is not through has
  # no still, so it is not in here at all and the thumbnail is the play
  # mark alone.
  defp poster_map(media) do
    media
    |> Enum.flat_map(fn {path, entry} ->
      if Videos.video?(path) and is_binary(entry.still) do
        [
          {"/uploads/#{path}",
           %{
             poster: "/renditions/320/#{entry.still}",
             full: "/renditions/max/#{entry.still}",
             film: entry.film && "/uploads/#{entry.film}"
           }}
        ]
      else
        []
      end
    end)
    |> Map.new()
  end

  # What the admin area says while ffmpeg is not through with a video.
  defp conversion_note(%{state: :queued}), do: "waiting to be converted"
  defp conversion_note(%{state: :running}), do: "converting"
  defp conversion_note(%{state: :none}), do: "waiting to be converted"
  defp conversion_note(%{state: :failed, error: nil}), do: "the conversion failed"
  defp conversion_note(%{state: :failed, error: reason}), do: "the conversion failed: #{reason}"
  defp conversion_note(_media), do: nil

  defp tile_count(gallery) do
    case length(gallery) do
      1 -> "1 tile"
      n -> "#{n} tiles"
    end
  end

  defp preview_candidates(%{article: article, gallery: gallery}) do
    Gallery.preview_candidates(article, Enum.map(gallery, & &1.path))
  end

  defp effective_preview(%{article: article, gallery: gallery}) do
    Gallery.effective_preview(article, Enum.map(gallery, & &1.path))
  end

  # A candidate can come from the body, so the path is markdown text;
  # a quote must not break out of the url('...') it lands in.
  defp tile_bg(path) do
    "background-image:url('/renditions/320/#{String.replace(path, "'", "%27")}')"
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

      # Another admin may have moved the entry, and the address it left
      # behind belongs on this screen too.
      {:noreply, socket |> assign(:article, article) |> load_redirects()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:article_deleted, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply,
       socket
       |> put_flash(:info, "The text was deleted while you had it open.")
       |> push_navigate(to: ~p"/admin/texts")}
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

  # A comment arrived, went, or its address was confirmed. Confirming
  # names no text, so every open editor reloads its own list on it.
  def handle_info({:comment_posted, %{article_id: id}}, socket) do
    {:noreply, maybe_reload_comments(socket, id)}
  end

  def handle_info({:comment_deleted, %{article_id: id}}, socket) do
    {:noreply, maybe_reload_comments(socket, id)}
  end

  def handle_info({:comment_changed, %{article_id: id}}, socket) do
    {:noreply, maybe_reload_comments(socket, id)}
  end

  def handle_info({:comments_confirmed, _address_id}, socket) do
    {:noreply, maybe_reload_comments(socket, socket.assigns.article.id)}
  end

  def handle_info({:setting_changed, :comments_require_confirmation, value}, socket) do
    {:noreply, assign(socket, :cmt_require, value)}
  end

  # A conversion moved on. The panel and the tiles read where it stands
  # while they render; this is the nudge that makes a render happen.
  def handle_info({:video_changed, path}, socket) do
    socket =
      if in_this_text?(socket, path), do: update(socket, :media_rev, &(&1 + 1)), else: socket

    # The panel and the tiles read the state as they render; the
    # writing surface is the hook's, so its posters are handed over.
    # Every editor is asked, not only the ones that already know the
    # video: a reference pasted a moment ago is still on its way here.
    {:noreply, sync_posters(socket)}
  end

  def handle_info(:reset_save_label, socket) do
    {:noreply, socket |> assign(:save_label, "Save version") |> assign(:save_timer, nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp in_this_text?(socket, path) do
    Enum.any?(socket.assigns.gallery, &(&1.path == path)) or
      String.contains?(to_string(socket.assigns.article.body), path)
  end

  defp maybe_reload_comments(socket, article_id) do
    if article_id == socket.assigns.article.id do
      assign(socket, :comments, Comments.for_article(article_id))
    else
      socket
    end
  end

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

  # The two ways an address can be refused, in the words of the note.
  defp slug_error(changeset) do
    case changeset.errors[:slug] do
      {"is an address the site itself uses", _} -> "That address belongs to the site itself"
      _ -> "That address is taken by another text"
    end
  end

  ## Saved state

  @note_ms 4600

  # How long the Save version button keeps its answer before it is a
  # button again. The same window the Last-saved line flashes for.
  @button_ms 2600

  defp say_on_button(socket, label) do
    if timer = socket.assigns[:save_timer], do: Process.cancel_timer(timer)

    socket
    |> assign(:save_label, label)
    |> assign(:save_timer, Process.send_after(self(), :reset_save_label, @button_ms))
  end

  defp mark_saved(socket, note \\ nil) do
    now = System.system_time(:millisecond)

    socket
    |> assign(:saved_at, now)
    |> assign(:saved_note, note)
    |> assign(:saved_until, if(note, do: now + @note_ms, else: 0))
  end

  # The suggestions keep their order while the editor is open: a tag
  # another text carries keeps its chip when this one drops it, so one
  # more click puts it back, and new tags join the end of the row.
  # Nothing under the pointer moves while somebody is clicking.
  #
  # A tag no text carries any more is off the blog, so it leaves the
  # row with the text it stood on. Without that, a word typed by
  # mistake would keep a chip until the editor is closed.
  defp known_tags(socket) do
    standing = socket.assigns[:known_tags] || []
    carried = Articles.known_tags() ++ Articles.tag_list(socket.assigns.article)

    kept = Enum.filter(standing, &(&1 in carried))

    assign(socket, :known_tags, kept ++ Enum.uniq(Enum.reject(carried, &(&1 in kept))))
  end

  defp reload_history(socket) do
    socket
    |> assign(:versions, Articles.versions(socket.assigns.article))
    |> assign(:log, Articles.log(socket.assigns.article))
  end

  defp load_redirects(socket) do
    assign(socket, :redirects, Articles.redirects(socket.assigns.article))
  end

  ## Render

  def render(assigns) do
    # once per render, not once per tile: the candidates parse the body,
    # and the stills ask in one go what every video of this text shows
    assigns =
      assigns
      |> assign(:preview_candidates, preview_candidates(assigns))
      |> assign(:effective_preview, effective_preview(assigns))
      |> assign(:media, media(assigns))
      |> assign(:public_url, Articles.reader_path(assigns.article))
      |> assign(:public_title, public_title(assigns.article))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={Articles.display_title(@article)}
      active="texts"
      others={@others}
    >
      <:bar>
        <%!-- the way out to the reader's side. An entry wears its
             address from the moment it has a slug, and the site serves
             an unpublished one to whoever is signed in, so the stamp
             and the Last-saved line are both that door. --%>
        <a
          :if={@public_url}
          class={["stamp out hidden sm:inline-flex", @article.status]}
          id="stamp"
          href={@public_url}
          target="_blank"
          rel="noopener"
          title={@public_title}
        >
          {@article.status}<.out_icon />
        </a>
        <span :if={!@public_url} class={["stamp hidden sm:inline", @article.status]} id="stamp">
          {@article.status}
        </span>
        <a
          :if={@public_url}
          class="out hidden md:inline-flex items-baseline flex-none"
          id="stateLink"
          href={@public_url}
          target="_blank"
          rel="noopener"
          title={@public_title}
        >
          <span
            class="saved whitespace-nowrap num"
            id="state"
            phx-hook="SavedTicker"
            data-at={@saved_at}
            data-note={@saved_note}
            data-note-until={@saved_until}
          >
            Last saved · just now
          </span>
          <.out_icon />
        </a>
        <span
          :if={!@public_url}
          class="saved hidden md:inline-block whitespace-nowrap num"
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
          {@save_label}
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
        <a
          :if={@public_url}
          class="row sm:hidden"
          id="viewRow"
          href={@public_url}
          target="_blank"
          rel="noopener"
        >
          Open the entry <.out_icon />
        </a>
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

      <%!-- Two columns, one scrollbar each and no third one. The words
           are the page: they scroll with the browser's own bar, however
           long the entry gets. The article settings stand still beside
           them, one screen tall, with a bar of their own that is always
           drawn (.sidecol), so the column never looks like it ends
           where the window does. --%>
      <div class="xl:grid xl:grid-cols-[minmax(0,1fr)_380px] lg:grid lg:grid-cols-[minmax(0,1fr)_320px]">
        <div class="min-w-0" id="textCol">
          <div class="max-w-[680px] mx-auto px-[14px] lg:px-[30px] pt-[22px] lg:pt-[30px] pb-10 lg:pb-[110px]">
            <%!-- the lock banner: the only place that tells the lock
                 story. There is no button on it, because clicking into
                 the title or the body already asks. --%>
            <div
              :if={
                (!@holds_lock && @holder) || (@holds_lock && reading_along(@others, @article) != [])
              }
              class={[
                "rounded-[5px] px-[13px] py-2 text-[13px] leading-[1.55] mb-5",
                if(@holds_lock, do: "bg-accentwash text-accent", else: "bg-livetint text-livetext")
              ]}
              id="jbar"
              style={"box-shadow: inset 0 0 0 1px var(--tt-#{if @holds_lock, do: "accentline", else: "liveline"})"}
            >
              <%!-- one running line, not a name column and a text
                   column: a second line of it starts at the left edge
                   like the first, and nothing is indented under the
                   name --%>
              <span class="dot live text-julia"></span>
              <b class="text-julia">
                {if @holds_lock,
                  do: Enum.join(reading_along(@others, @article), ", "),
                  else: holder_name(@holder)}
              </b>
              <span class="opacity-85">
                <%= if @holds_lock do %>
                  reads along while you write. The article settings stay open to every admin, at the same time.
                <% else %>
                  writes the text now, and you see it in real time. Click into the title or the body to take the text over. The article settings can be changed by everyone independently from title or body.
                <% end %>
              </span>
            </div>

            <nav
              class="flex gap-0.5 border-b border-rule mb-6 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
              aria-label="Text sections"
            >
              <button
                :for={
                  {tab, label} <- [
                    {"text", "Text"},
                    {"comments", "Comments"},
                    {"log", "Log"},
                    {"versions", "Versions"}
                  ]
                }
                class={["tab", @tab == tab && "on"]}
                phx-click="set_tab"
                phx-value-tab={tab}
              >
                {label}
                <span :if={tab == "versions" && @versions != []} class="cnt">
                  {length(@versions)}
                </span>
                <span :if={tab == "comments" && @comments != []} class="cnt">
                  {length(@comments)}
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
              <.md_bar id="mdBar" readonly={!@holds_lock} note="Markdown Editor" />
              <div class={["relative", !@holds_lock && "is-readonly"]} id="bodyWrap">
                <div
                  id="edBodyHost"
                  class="ed-body ed-cm"
                  phx-hook="BodyEd"
                  phx-update="ignore"
                  data-readonly={to_string(!@holds_lock)}
                  data-posters={Jason.encode!(poster_map(@media))}
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
                      The draft saves as you type. <b>Save version</b>
                      takes a snapshot of the title and the body that you can go back to.
                    <% else %>
                      The title and the body are read-only right now. <b>Save version</b>
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
                accept="image/*,video/*"
                aria-label="Put pictures and videos in the text"
              />

              <%!-- the images in the text: a reading of the body, never
                   a list of its own. An upload that is still running
                   holds its place with a token, and the token becomes
                   the reference when the upload finishes. --%>
              <div class="mt-[34px]">
                <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
                  <span class="text-[13px] font-semibold">
                    Pictures and videos in the text
                    <span class="note num" id="inlineCount">{inline_count(@article.body)}</span>
                  </span>
                  <span class="sp"></span>
                  <span class="note">Paste one into the text, or drop one on it.</span>
                </div>
                <div id="inlineImgs">
                  <p :if={Articles.inline_refs(@article.body) == []} class="note pt-[10px]">
                    None in this text yet. Paste a picture or a video into the text, or drop one on it.
                  </p>
                  <%= for ref <- Articles.inline_refs(@article.body) do %>
                    <% media = ref_media(@media, ref.url) %>
                    <%!-- a picture, or a video ffmpeg is through with:
                         the still stands for it. A video that is not
                         converted yet says where it stands instead. --%>
                    <div
                      :if={ref.kind == :done}
                      class="flex items-center gap-[11px] py-[9px] border-b border-hair text-[13px]"
                    >
                      <span
                        :if={media && media.still}
                        class="w-9 h-9 r-img bg-field bg-center bg-cover flex-none"
                        style={"background-image:url('#{thumb_url("/uploads/" <> media.still)}')"}
                      >
                      </span>
                      <span :if={media && !media.still} class="w-9 h-9 r-img bg-field flex-none">
                      </span>
                      <span
                        :if={!media}
                        class="w-9 h-9 r-img bg-field bg-center bg-cover flex-none"
                        style={"background-image:url('#{thumb_url(ref.url)}')"}
                      >
                      </span>
                      <span class="font-semibold flex-none">{ref.file}</span>
                      <span :if={media && conversion_note(media)} class="note">
                        {conversion_note(media)}
                      </span>
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

            <div :if={@tab == "comments"} id="tp-comments">
              <p :if={@comments == []} class="note max-w-[62ch]">
                No comments yet. {comment_rule(@cmt_require)}
              </p>
              <div :if={@comments != []}>
                <.comment_item
                  :for={comment <- @comments}
                  comment={comment}
                  waiting={Comments.waiting?(comment, @cmt_require)}
                  editing={@editing_comment == to_string(comment.id)}
                  error={@comment_error}
                />
                <p class="note mt-[14px] max-w-[62ch]">
                  {comments_foot(@comments, @cmt_require)}
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
                The <b>Save version</b>
                button in the bar saves the current version of the title and the body. Article settings are never versioned, because they are shared and live. Every version below shows what changed against the one before it, and can be restored.
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
          class="sidecol min-w-0 bg-paper border-t lg:border-t-0 lg:border-l border-rule px-[14px] lg:px-6 pt-[22px] pb-[50px] lg:pb-[55px]"
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
            data-upload-url={~p"/admin/texts/#{@article.id}/gallery"}
            data-csrf={Phoenix.Controller.get_csrf_token()}
          >
            <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
              <span class="text-[13px] font-semibold">
                Tiles <span class="note num" id="tileCount">{tile_count(@gallery)}</span>
                <span class="note num" id="tileOnWay" phx-update="ignore"></span>
              </span>
              <span class="sp"></span>
              <span class="note">Grab a tile to sort it.</span>
            </div>
            <div class="grid gap-[6px] grid-cols-3 lg:grid-cols-2 xl:grid-cols-3 mt-3" id="tileGrid">
              <div class="contents" id="tileServer">
                <div
                  :for={{image, index} <- Enum.with_index(@gallery, 1)}
                  class={["tile", !@media[image.path].still && "tile-waiting"]}
                  id={"tile-#{image.id}"}
                  data-id={image.id}
                  data-rev={@gallery_rev}
                  data-filename={image.filename}
                  data-date={Calendar.strftime(image.gallery_date, "%Y-%m-%dT%H:%M")}
                  data-full={
                    @media[image.path].still && "/renditions/max/#{@media[image.path].still}"
                  }
                  data-video={@media[image.path].film && "/uploads/#{@media[image.path].film}"}
                  data-original={"/uploads/" <> image.path}
                  title={"#{image.filename} · #{Calendar.strftime(image.gallery_date, "%Y-%m-%d")}"}
                  style={@media[image.path].still && tile_bg(@media[image.path].still)}
                  role="button"
                  tabindex="0"
                  aria-label={"Tile #{index}, #{image.filename}, grab to sort, tap to see it big"}
                >
                  <span class="n">{String.pad_leading("#{index}", 2, "0")}</span>
                  <span :if={@effective_preview == image.path} class="cov">preview</span>
                  <span :if={@media[image.path].film} class="play-badge" aria-hidden="true"></span>
                  <span :if={conversion_note(@media[image.path])} class="tile-wait">
                    {conversion_note(@media[image.path])}
                  </span>
                  <button
                    type="button"
                    class="tile-del"
                    data-del
                    aria-label={"Delete #{image.filename}"}
                  >
                    &times;
                  </button>
                </div>
              </div>
              <div class="contents" id="tileLocal" phx-update="ignore"></div>
              <button
                type="button"
                class="tile-add"
                id="tileAdd"
                aria-label="Add pictures and videos"
              >
                + Add
              </button>
            </div>
            <input
              type="file"
              id="tileFiles"
              class="sr"
              multiple
              accept="image/*,video/*"
              aria-label="Add pictures and videos to the gallery"
            />
            <span class="drop-flag" id="tileDropFlag" hidden>
              Add it to the gallery, at the end
            </span>
            <%!-- what the grid has to say for a moment: a tile another
                 admin moved, a file over the roof, an upload that
                 failed. The rule stands over the grid, so this line has
                 nothing to say the rest of the time and is not there. --%>
            <p class="note mt-[10px] transition-colors empty:hidden" id="tileNote"></p>
          </div>

          <.share_block article={@article} />

          <%!-- article settings: what the text wears first (preview,
               address, date), then what it is, then its community.
               No Status row - the stamp and the button in the bar
               already say it - and no Publish button either. --%>
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
              <span class="lab">Preview image</span>
              <span class="val">
                <div class="flex flex-wrap gap-[6px] items-center" id="coverRow">
                  <%= if @preview_candidates == [] do %>
                    <span class="note">
                      No pictures yet. Once the text or the gallery has one, pick it here.
                    </span>
                  <% else %>
                    <button
                      :for={
                        {path, index} <- @preview_candidates |> Enum.take(8) |> Enum.with_index(1)
                      }
                      type="button"
                      class={["cover-opt", @effective_preview == path && "on"]}
                      style={tile_bg((@media[path] && @media[path].still) || path)}
                      phx-click="set_preview"
                      phx-value-path={path}
                      aria-label={"Use image #{index} as the preview image"}
                    >
                    </button>
                    <span :if={length(@preview_candidates) > 8} class="note">
                      +{length(@preview_candidates) - 8} more in the gallery
                    </span>
                  <% end %>
                </div>
                <div class="hint">
                  Used in the texts grid, on the front page and in link previews.
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">Address</span>
              <span class="val">
                <span class="addr">
                  <span class="pre">
                    {TexttileWeb.Endpoint.host()}{Articles.public_prefix(@article)}
                  </span>
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
                <%!-- every address this entry used to answer at. They
                     are kept so a link somebody shared still arrives;
                     a row that is not worth keeping goes with one
                     click, and then the address is a 404 again. --%>
                <div :if={@redirects != []} class="oldaddr" id="oldAddresses">
                  <p class="lab">Old addresses, still arriving here</p>
                  <div :for={old <- @redirects} class="row" id={"oldaddr-#{old.id}"}>
                    <a
                      class="p"
                      href={old.path}
                      target="_blank"
                      rel="noopener"
                      title="Follows the old address, in a new tab"
                    >
                      {old.path}
                    </a>
                    <button
                      type="button"
                      class="btn quiet sm"
                      phx-click="delete_redirect"
                      phx-value-id={old.id}
                      aria-label={"Stop answering #{old.path}"}
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="labrow">
                <label class="lab" id="edDateLab" for="edDate">
                  {if @article.status == "scheduled", do: "Goes live", else: "Publish date"}
                </label>
                <%!-- a date field empties badly by hand, so the row
                     offers the one word for it. On a live entry it is
                     the same statement as Unpublish, and the hint under
                     the field says so. --%>
                <button
                  :if={@article.publish_date}
                  type="button"
                  class="link"
                  id="edDateReset"
                  phx-click="clear_publish_date"
                >
                  Reset
                </button>
              </span>
              <span class="val">
                <input type="date" id="edDate" name="publish_date" value={@article.publish_date} />
                <div class="hint" id="edDateHint">{date_hint(@article)}</div>
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
                    Page<span class="note">Standalone Page, like About or Imprint. Appears in the site menu sorted by publish date, never in the feed.</span>
                  </span>
                </label>
              </span>
            </div>

            <div :if={@article.type != "page"} class="drow" id="fieldTags">
              <span class="lab">Tags</span>
              <span class="val">
                <%!-- the field completes itself out of the tags the
                     blog already carries; the hook owns the list it
                     drops under the field.

                     A half-written word is no tag, so the field waits:
                     it hands the row over when it loses the focus, and
                     the hook hands it over earlier the moment a comma
                     closes a word. --%>
                <input
                  type="text"
                  id="edTags"
                  name="tags"
                  value={@article.tags}
                  aria-label="Tags"
                  phx-debounce="blur"
                  phx-hook=".TagType"
                  data-tags={Enum.join(@known_tags, "\n")}
                  autocomplete="off"
                  spellcheck="false"
                  role="combobox"
                  aria-expanded="false"
                  aria-autocomplete="list"
                  aria-controls="tagMenu"
                />
                <script :type={Phoenix.LiveView.ColocatedHook} name=".TagType">
                  // The tag field completes what you are typing out of
                  // the tags the blog already carries. The field holds a
                  // comma-separated row, so only the word after the last
                  // comma is completed. The menu lives on the body and is
                  // placed by hand: the side column scrolls, and a menu
                  // inside it would be cut off at its edge.
                  const MAX = 8

                  export default {
                    mounted() {
                      this.menu = document.createElement("ul")
                      this.menu.id = "tagMenu"
                      this.menu.className = "tagmenu"
                      this.menu.setAttribute("role", "listbox")
                      this.menu.hidden = true
                      document.body.appendChild(this.menu)

                      this.at = -1
                      this.matches = []
                      this.commas = this.count()

                      this.onInput = () => { this.commit(); this.refresh() }
                      this.onKey = e => this.key(e)
                      this.onBlur = () => setTimeout(() => this.close(), 120)
                      this.onPlace = () => { if (!this.menu.hidden) this.place() }

                      this.el.addEventListener("input", this.onInput)
                      this.el.addEventListener("keydown", this.onKey)
                      this.el.addEventListener("blur", this.onBlur)
                      window.addEventListener("resize", this.onPlace)
                      window.addEventListener("scroll", this.onPlace, true)

                      // pointerdown, not click: the field blurs first
                      this.menu.addEventListener("pointerdown", e => {
                        const row = e.target.closest("[data-tag]")
                        if (!row) return
                        e.preventDefault()
                        this.accept(row.dataset.tag)
                      })
                    },

                    // the server wrote the row back: count what stands
                    // there now, so the next comma is a new one
                    updated() { this.commas = this.count() },

                    count() { return (this.el.value.match(/,/g) || []).length },

                    // A word is a tag once it is finished, and a comma
                    // finishes it. The field itself waits for the blur,
                    // so this is the earlier way in: one more comma,
                    // one push of the whole row.
                    commit() {
                      const commas = this.count()
                      if (commas > this.commas) {
                        this.pushEvent("settings_changed", {_target: ["tags"], tags: this.el.value})
                      }
                      this.commas = commas
                    },

                    destroyed() {
                      this.el.removeEventListener("input", this.onInput)
                      this.el.removeEventListener("keydown", this.onKey)
                      this.el.removeEventListener("blur", this.onBlur)
                      window.removeEventListener("resize", this.onPlace)
                      window.removeEventListener("scroll", this.onPlace, true)
                      this.menu.remove()
                    },

                    known() {
                      return (this.el.dataset.tags || "").split("\n").filter(Boolean)
                    },

                    // everything before the last comma stays as it is;
                    // the rest is the word being written
                    parts() {
                      const value = this.el.value
                      const cut = value.lastIndexOf(",")
                      return {
                        head: cut === -1 ? "" : value.slice(0, cut + 1),
                        word: (cut === -1 ? value : value.slice(cut + 1)).trim(),
                      }
                    },

                    written() {
                      return this.el.value.split(",").map(t => t.trim().toLowerCase()).filter(Boolean)
                    },

                    refresh() {
                      const {word} = this.parts()
                      const term = word.toLowerCase()
                      if (!term) return this.close()

                      const taken = this.written()
                      const hits = this.known().filter(
                        tag => tag.includes(term) && !taken.includes(tag)
                      )
                      // what the word starts, before what it only touches
                      hits.sort((a, b) => a.startsWith(term) === b.startsWith(term) ? 0 : a.startsWith(term) ? -1 : 1)

                      this.matches = hits.slice(0, MAX)
                      if (!this.matches.length) return this.close()

                      this.at = 0
                      this.paint()
                      this.open()
                    },

                    paint() {
                      this.menu.replaceChildren(...this.matches.map((tag, i) => {
                        const row = document.createElement("li")
                        row.dataset.tag = tag
                        row.textContent = tag
                        row.setAttribute("role", "option")
                        row.setAttribute("aria-selected", i === this.at ? "true" : "false")
                        if (i === this.at) row.classList.add("on")
                        return row
                      }))
                    },

                    place() {
                      const r = this.el.getBoundingClientRect()
                      this.menu.style.left = `${r.left}px`
                      this.menu.style.width = `${r.width}px`
                      this.menu.style.top = `${r.bottom + 4}px`
                    },

                    open() {
                      this.menu.hidden = false
                      this.el.setAttribute("aria-expanded", "true")
                      this.place()
                    },

                    close() {
                      this.menu.hidden = true
                      this.el.setAttribute("aria-expanded", "false")
                      this.at = -1
                      this.matches = []
                    },

                    key(e) {
                      if (this.menu.hidden) return
                      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                        e.preventDefault()
                        const step = e.key === "ArrowDown" ? 1 : -1
                        this.at = (this.at + step + this.matches.length) % this.matches.length
                        this.paint()
                      } else if (e.key === "Enter" || e.key === "Tab") {
                        if (this.at < 0) return
                        e.preventDefault()
                        this.accept(this.matches[this.at])
                      } else if (e.key === "Escape") {
                        e.preventDefault()
                        this.close()
                      }
                    },

                    // the completed tag, and a comma ready for the next
                    accept(tag) {
                      const {head} = this.parts()
                      this.el.value = `${head ? head + " " : ""}${tag}, `
                      this.close()
                      this.el.focus()
                      this.el.dispatchEvent(new Event("input", {bubbles: true}))
                    },
                  }
                </script>
                <%!-- the tags the blog already carries: one click puts
                     one in the field, one more takes it out again --%>
                <div :if={@known_tags != []} class="tagpick" id="tagPick">
                  <button
                    :for={tag <- @known_tags}
                    type="button"
                    class={["tagchip", tag in Articles.tag_list(@article) && "on"]}
                    id={"tagchip-#{Articles.slugify(tag)}"}
                    phx-click="toggle_tag"
                    phx-value-tag={tag}
                  >
                    {tag}
                  </button>
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">Community</span>
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

      <%!-- the one small dialog: delete, publish-anyway, the takeover,
           and the question before a comment goes --%>
      <.ask
        :if={@dialog}
        heading={@dialog.title}
        ok={@dialog.ok}
        on_ok={@dialog.event}
        value={@dialog[:value]}
      >
        <p :for={line <- @dialog.body} class="mt-[9px] first:mt-0">{line}</p>
      </.ask>
    </Layouts.app>
    """
  end

  @doc """
  What to hand somebody so they can read this text: the address it
  lives at, and the word the blog asks for while it is protected.

  The password stands here whatever the text is, a post or a page, and
  whether or not the text is live: a protected blog is protected
  everywhere, and the one place a writer looks at a text is this
  screen. The line to pass on arrives with the text going live, because
  before that there is no address to pass on.
  """
  attr :article, :any, required: true

  def share_block(assigns) do
    password = Texttile.Settings.get(:site_password)
    protected? = Texttile.Settings.get(:site_visibility) == "protected"

    assigns =
      assigns
      |> assign(:protected?, protected?)
      |> assign(:password, password)
      # A word nobody is asked for is worth showing anyway: it is the
      # word this blog uses, and the line beside it says whether the
      # gate is open. A blog that has neither says nothing at all.
      |> assign(:show_password?, protected? or password != "")
      |> assign(:password_hint, password_hint(protected?, password))
      |> assign(:share_text, share_text(assigns.article, protected? && password))

    ~H"""
    <div :if={@show_password? or @share_text} class="mt-[34px]" id="shareBlock">
      <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
        <span class="text-[13px] font-semibold">Share</span>
      </div>

      <div :if={@show_password?} class="drow pt-0.5" id="sharePassword">
        <span class="lab">Blog password</span>
        <span class="val">
          <span :if={@password != ""} class="font-mono text-[13.5px]" id="sharePasswordWord">
            {@password}
          </span>
          <span :if={@password == ""} class="note" id="sharePasswordMissing">
            None yet. The blog is set to protected, and without a word nothing
            is protected.
          </span>
          <div class="hint" id="sharePasswordHint">{@password_hint}</div>
        </span>
      </div>

      <div :if={@share_text} class="drow gtop" id="shareText">
        <span class="lab">To pass on</span>
        <span class="val">
          <div phx-hook=".CopyShare" id="shareCopy">
            <textarea
              id="shareLines"
              class="font-mono text-[12.5px] leading-[1.6] resize-none"
              rows={length(String.split(@share_text, "\n"))}
              readonly
              spellcheck="false"
              aria-label="The text to pass on"
            >{@share_text}</textarea>
            <div class="mt-[9px] btn-row">
              <button type="button" class="btn sm" data-copy>Copy</button>
              <span class="note" data-copied hidden>Copied</span>
            </div>
          </div>
          <div class="hint">
            The address of the text{if @protected? and @password != "",
              do: ", and the word that opens the blog",
              else: ""}. Subscribers get the same
            lines by mail when the text goes live.
          </div>
        </span>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyShare">
      export default {
        mounted() { this.wire() },
        updated() { this.wire() },
        wire() {
          const button = this.el.querySelector("[data-copy]")
          const said = this.el.querySelector("[data-copied]")
          const field = this.el.querySelector("textarea")
          if (!button || button.dataset.wired) return
          button.dataset.wired = "1"
          button.addEventListener("click", async () => {
            try {
              await navigator.clipboard.writeText(field.value)
            } catch (_error) {
              // No clipboard permission, and no browser offers one on
              // plain http. The words are selected instead, so one key
              // still copies them.
              field.select()
            }
            if (said) {
              said.hidden = false
              clearTimeout(this.timer)
              this.timer = setTimeout(() => { said.hidden = true }, 2200)
            }
          })
        }
      }
    </script>
    """
  end

  # The lines a writer hands on: the title, the address, and the word
  # the blog asks for. Nil while the text has no address of its own,
  # which is every text that is not live yet.
  defp password_hint(true = _protected?, _password) do
    "The whole blog waits behind this one word, this text with it. " <>
      "Settings > Access is where it changes."
  end

  defp password_hint(false, _password) do
    "The blog is open right now, so nobody is asked for this word. " <>
      "Settings > Access turns the gate on."
  end

  defp share_text(%{status: status}, _password) when status != "published", do: nil

  defp share_text(article, password) do
    case Articles.public_path(article) do
      nil ->
        nil

      path ->
        head =
          "New on #{Texttile.Settings.site_title()}: " <>
            Articles.display_title(article) <> "\n" <> TexttileWeb.Endpoint.url() <> path

        case password do
          word when is_binary(word) and word != "" -> head <> "\nThe blog password is: " <> word
          _ -> head
        end
    end
  end

  # What the door to the reader's side promises, in the words of the
  # state it opens: a live entry is the page everybody reads, and one
  # that is not live yet is that page for the admins alone.
  defp public_title(%{status: "published"}),
    do: "Opens the entry on the public site, in a new tab"

  defp public_title(_article),
    do:
      "Opens the entry as it was last saved, in a new tab. " <>
        "Only somebody signed in can open this address."

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

  # Whatever an admin does on the Comments tab, it does it to a comment
  # of the open text. Anything else is left alone without a word.
  defp own_comment(socket, id, fun) do
    article_id = socket.assigns.article.id

    case Comments.get_comment(id) do
      %{article_id: ^article_id} = comment -> fun.(comment)
      _ -> {:error, :gone}
    end
  end

  defp close_comment_edit(socket) do
    socket |> assign(:editing_comment, nil) |> assign(:comment_error, nil)
  end

  defp reload_comments(socket) do
    assign(socket, :comments, Comments.for_article(socket.assigns.article.id))
  end

  # The note under the comment list: who still stands outside the text,
  # or the rule when nobody does.
  defp comments_foot(comments, require?) do
    case Enum.count(comments, &Comments.waiting?(&1, require?)) do
      0 ->
        comment_rule(require?)

      1 ->
        "1 comment is still out of the text: that reader has not followed the confirmation link yet."

      n ->
        "#{n} comments are still out of the text: those readers have not followed the confirmation link yet."
    end
  end

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

  # Who else has this text open right now, by name; read from the
  # admin presence the wordmark menu already carries.
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

    "#{done} #{if done == 1, do: "file", else: "files"}" <>
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

  defp date_hint(%{status: "draft"}),
    do: "Empty means whenever you publish. A future date schedules the text."

  defp date_hint(%{status: "scheduled"} = article) do
    if article.publish_date,
      do: "Scheduled. The subscriber email goes out on #{article.publish_date}.",
      else: "Pick the day it goes live."
  end

  defp date_hint(article) do
    if article.publish_date,
      do:
        "Live since #{article.publish_date}. A future date changes it to unpublished until the date.",
      else: "Pick the day it went live. An empty field makes the entry a draft again."
  end

  defp slug_hint(%{status: "draft"}), do: "Free to change while the text is a draft."

  defp slug_hint(article) do
    "#{TexttileWeb.Endpoint.host()}#{Articles.public_path(article)} is live; changing it breaks old links."
  end

  # The stamp outranks the status: a text that carried its email out
  # once never sends it again, whatever state it stands in now.
  defp notify_note(%{notified_on: %Date{} = day}),
    do:
      "The subscriber email for this text went out on #{day}. It goes out once; publishing again does not send it again."

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
    do: "No email went out for this text. The email goes out only at the moment a text goes live."
end
