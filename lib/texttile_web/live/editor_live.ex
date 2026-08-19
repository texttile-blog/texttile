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
  import TexttileWeb.StatsComponents
  import Texttile.Articles.Editing, only: [holding: 1]

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Articles.Body
  alias Texttile.Articles.Editing
  alias Texttile.Articles.Lock
  alias Texttile.Articles.Publishing
  alias Texttile.Articles.Visibility
  alias Texttile.Comments
  alias Texttile.Gallery
  alias Texttile.I18n
  alias Texttile.Images
  alias Texttile.Stats
  alias Texttile.Videos
  alias TexttileWeb.UploadNews

  ## Mount

  def mount(%{"id" => id}, _session, socket) do
    article = Articles.get_article!(id)
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign_article(article)
      |> assign(:tab, "text")
      |> assign(:state_menu, false)
      |> assign(:dialog, nil)
      |> assign(:saved_at, DateTime.to_unix(article.updated_at, :millisecond))
      |> assign(:saved_note, nil)
      |> assign(:saved_until, 0)
      |> assign(:editing, %Editing{state: :writing})
      |> assign(:upload_pcts, %{})
      |> assign(:versions, Articles.versions(article))
      |> assign(:log, Articles.log(article))
      |> assign(:redirects, Articles.redirects(article))
      |> assign(:gallery, Gallery.list(article.id))
      |> assign(:gallery_rev, 0)
      |> assign(:media_rev, 0)
      |> assign(:comments, Comments.for_article(article.id))
      |> assign(:cmt_require, Texttile.Settings.get(:comments_require_confirmation))
      # The accounts the Author field offers. All admins are equal, so
      # every one of them can carry an entry.
      |> assign(:accounts, Accounts.list_users_and_deleted())
      |> TexttileWeb.CommentModeration.attach(
        scope: {:article, & &1.assigns.article.id},
        reload: &reload_comments/1
      )
      # The numbers are read when the Stats tab is opened, not on the
      # way into the editor: most visits here are to write.
      |> assign(:stats, nil)
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

        socket = assign(socket, :editing, Editing.start(article.id, user.id, self()))

        announce_activity(socket)
      else
        socket
      end

    {:ok, assign(socket, :page_title, Articles.display_title(article))}
  end

  # The Comments overview jumps straight into a text's Comments tab;
  # the address may name any tab.
  def handle_params(%{"tab" => tab}, _uri, socket)
      when tab in ~w(text comments stats log versions) do
    {:noreply, socket |> assign(:tab, tab) |> load_stats(tab)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # The wordmark menu and the other editor's banner read this: which
  # text this tab is in, and whether it writes or reads along.
  defp announce_activity(socket) do
    %{article: article, current_scope: scope, editing: editing} = socket.assigns
    holds = Editing.holds?(editing)

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
    if Editing.holds?(socket.assigns.editing) do
      {:ok, article} = Articles.update_text(socket.assigns.article, %{body: text})
      Lock.ping(article.id, self())

      # A video pasted a moment ago reaches the server with this text
      # and may be converted already; its poster goes back with the
      # answer, because the conversion's own word came too early to
      # find the reference here.
      {:noreply, socket |> assign_article(article) |> sync_posters() |> mark_saved()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("editor_activity", _params, socket) do
    if Editing.holds?(socket.assigns.editing), do: Lock.ping(socket.assigns.article.id, self())
    {:noreply, socket}
  end

  # The client's answer to flush_body: the keystrokes that were still
  # in its debounce when the takeover started.
  def handle_event("body_flushed", %{"text" => text}, socket) do
    socket =
      if Editing.holds?(socket.assigns.editing) and text != socket.assigns.article.body do
        {:ok, article} = Articles.update_text(socket.assigns.article, %{body: text})
        assign_article(socket, article)
      else
        socket
      end

    {:noreply, finish_flush(socket)}
  end

  # The button answers for itself. A version is not a save of the text -
  # the text saved itself while it was typed - so the news belongs on
  # the control that was pressed, not on the Last-saved line beside it.
  # Save version is a row of the publish menu now, and a row that is
  # clicked closes its menu, so the answer cannot be written on the
  # control itself. It goes where every other answer of this screen
  # goes: the state line.
  def handle_event("save_version", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    socket = assign(socket, :state_menu, false)

    case Articles.save_version(article, scope.user) do
      {:ok, _version} ->
        {:noreply,
         socket
         |> reload_history()
         |> mark_saved(gettext("Version saved · the Versions tab shows what changed"))}

      :unchanged ->
        {:noreply, mark_saved(socket, gettext("Nothing changed since the last version"))}
    end
  end

  def handle_event("restore_version", %{"id" => id}, socket) do
    %{article: article, current_scope: scope, versions: versions} = socket.assigns

    cond do
      not Editing.holds?(socket.assigns.editing) ->
        {:noreply, mark_saved(socket, gettext("Take the entry over first; restoring needs it"))}

      version = Enum.find(versions, &(to_string(&1.id) == id)) ->
        {:ok, article} = Articles.restore_version(article, version, scope.user)

        {:noreply,
         socket
         |> assign_article(article)
         |> push_event("sync_body", %{text: article.body})
         |> mark_saved(
           gettext("Version from %{stamp} restored", stamp: stamp(version.inserted_at))
         )}

      true ->
        {:noreply, socket}
    end
  end

  ## Events · the takeover

  def handle_event("ask_takeover", _params, socket) do
    article = socket.assigns.article

    case Editing.who_holds(article.id, self()) do
      free_or_mine when free_or_mine in [:free, :mine] ->
        {:noreply, refresh_lock(socket)}

      {:held, holder} ->
        name = holder_name(holder)

        {:noreply,
         assign(socket, :dialog, %{
           id: "takeover",
           title: gettext("Take the entry over from %{name}?", name: name),
           body: [
             activity_line(name, holder),
             "A takeover stops that mid-sentence. The title and the body turn read-only on the other side, and a note says who took the entry. Nothing is lost, and the entry can go straight back."
           ],
           ok: gettext("Take over the entry"),
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

  # The one button at the end of the bar, and it means two different
  # things by the state it stands in.
  #
  # On a draft it is Publish, and the mail is part of it: the entry has
  # never been out, so this click is where the decision belongs.
  #
  # On a scheduled entry it is Publish now, which only moves the day
  # forward. The mail was decided when the entry was scheduled and the
  # menu beside this button still carries that decision, so the click
  # takes it as it stands instead of arming it again behind the
  # admin's back.
  def handle_event("publish", _params, socket) do
    {:noreply, ask_publish(socket, Publishing.choice(socket.assigns.article))}
  end

  # The same step with the mail left out. Nothing here is irreversible,
  # so nothing but the lock is worth a question.
  def handle_event("publish_quietly", _params, socket),
    do: {:noreply, ask_publish(socket, :quiet)}

  def handle_event("do_publish", %{"id" => mode}, socket)
      when mode in ~w(mail quiet as_set) do
    {:noreply, socket |> assign(:dialog, nil) |> publish_with(String.to_existing_atom(mode))}
  end

  def handle_event("do_publish", _params, socket) do
    {:noreply, socket |> assign(:dialog, nil) |> publish_with(:mail)}
  end

  # A scheduled entry keeps its date; only the mail at go-live changes.
  def handle_event("toggle_notify", _params, socket) do
    %{article: article} = socket.assigns
    wanted = !article.notify_on_publish

    {:ok, article} = Articles.update_settings(article, %{"notify_on_publish" => wanted})

    {:noreply,
     socket
     |> put_article(article)
     |> assign(:state_menu, false)
     |> reload_history()
     |> mark_saved(
       if(wanted,
         do: gettext("The subscribers get the mail when this goes live"),
         else: gettext("No mail goes out when this goes live")
       )
     )}
  end

  def handle_event("unpublish", _params, socket) do
    %{article: article, current_scope: scope} = socket.assigns
    was = article.status
    {:ok, article} = Articles.unpublish(article, scope.user)

    {:noreply,
     socket
     |> put_article(article)
     |> assign(:state_menu, false)
     |> reload_history()
     |> mark_saved(
       if(was == "scheduled",
         do: gettext("Unscheduled · a draft again"),
         else: gettext("Unpublished · a draft again")
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
            do: gettext("The date is empty · unscheduled, a draft again"),
            else: gettext("The date is empty · unpublished, a draft again")

        true ->
          nil
      end

    {:noreply,
     socket
     |> put_article(article)
     |> reload_history()
     |> load_redirects()
     |> mark_saved(note)}
  end

  # The Author field: the entry goes to another account. Open to every
  # admin, like the rest of the settings.
  def handle_event("settings_changed", %{"_target" => ["user_id" | _]} = params, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    case Articles.set_author(article, params["user_id"], by: scope.user) do
      {:ok, article} ->
        {:noreply, socket |> put_article(article) |> mark_saved()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:accounts, Accounts.list_users_and_deleted())
         |> mark_saved(gettext("That account is gone · the author stands"))}
    end
  end

  def handle_event("settings_changed", %{"_target" => [field | _]} = params, socket)
      when field in ~w(type tags slug allow_comments notify_on_publish) do
    %{article: article} = socket.assigns

    case Articles.update_settings(article, Map.take(params, [field])) do
      {:ok, article} ->
        socket = assign_article(socket, article)
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

    {:noreply,
     socket |> load_redirects() |> mark_saved(gettext("That address answers nothing again"))}
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
        {:noreply, socket |> assign_article(article) |> known_tags() |> mark_saved()}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  ## Events · chrome

  def handle_event("set_tab", %{"tab" => tab}, socket)
      when tab in ~w(text comments stats log versions) do
    {:noreply, socket |> assign(:tab, tab) |> load_stats(tab)}
  end

  # The six comment moderation events are answered by
  # CommentModeration, scoped to the open text's own comments. The
  # trash itself lives on the Comments screen; a text only ever
  # deletes into it.

  # Only ever opens. The chevron of an open menu says "close" instead,
  # because a click on it is also a click away from the menu, and the
  # menu answers that one too: a toggle here read the closing as a
  # second click and put the menu straight back up.
  def handle_event("open_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, true)}
  end

  def handle_event("close_state_menu", _params, socket) do
    {:noreply, assign(socket, :state_menu, false)}
  end

  # The words as they stand become the words the readers have. Only
  # the text moves: the same day, the same address, the same state,
  # and no mail, because the mail belongs to the entry going out and
  # not to a correction inside it.
  def handle_event("publish_changes", _params, socket) do
    case Articles.publish_changes(socket.assigns.article, socket.assigns.current_scope.user) do
      {:ok, article} ->
        {:noreply,
         socket
         |> assign(:state_menu, false)
         |> put_article(article)
         |> reload_history()
         |> mark_saved(gettext("Published · the readers have these words now"))}

      :unchanged ->
        {:noreply, assign(socket, :state_menu, false)}
    end
  end

  def handle_event("ask_discard", _params, socket) do
    {:noreply,
     socket
     |> assign(:state_menu, false)
     |> assign(:dialog, %{
       id: "discard",
       title: gettext("Throw the unpublished changes away?"),
       body: [
         gettext(
           "The text goes back to the words the readers have. What is written here now is kept as a version, so you can bring it back from the Versions tab."
         )
       ],
       ok: gettext("Discard the changes"),
       event: "confirm_discard"
     })}
  end

  def handle_event("confirm_discard", _params, socket) do
    case Articles.discard_changes(socket.assigns.article, socket.assigns.current_scope.user) do
      {:ok, article} ->
        {:noreply,
         socket
         |> assign(:dialog, nil)
         |> put_article(article)
         |> reload_history()
         |> mark_saved(gettext("The changes are gone · the published text is back"))}

      _ ->
        {:noreply, assign(socket, :dialog, nil)}
    end
  end

  def handle_event("ask_delete", _params, socket) do
    article = socket.assigns.article

    live_line =
      if Visibility.live?(article) do
        address = TexttileWeb.Endpoint.host() <> Articles.public_path(article)

        [
          gettext(
            "The entry is live. From now on, a reader who follows an old link to %{address} gets a 404 page.",
            address: address
          )
        ]
      else
        []
      end

    {:noreply,
     socket
     |> assign(:state_menu, false)
     |> assign(:dialog, %{
       id: "delete",
       title: gettext("Delete \"%{title}\"?", title: Articles.display_title(article)),
       body:
         [
           gettext(
             "This deletes the entry and everything that belongs to it: the title and the body, the images in the text, every saved version and the whole Log."
           )
         ] ++ live_line ++ [gettext("There is no undo.")],
       ok: gettext("Delete the entry"),
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
       gettext("\"%{title}\" is deleted. Its versions and its log went with it.",
         title: Articles.display_title(article)
       )
     )
     |> push_navigate(to: ~p"/admin/texts")}
  end

  def handle_event("cancel_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  ## Events · images in the text. The files and the running requests
  ## live in the holder's browser; the hook crosses the seam once per
  ## change with the standing state and the news (see uploads.js and
  ## UploadNews). The state becomes the progress display whoever sends
  ## it; a piece of news that writes into the entry or its Log only
  ## counts from the holder of the lock.

  def handle_event("upload_state", params, socket) do
    socket = assign(socket, :upload_pcts, UploadNews.pcts(params["files"]))

    socket =
      params
      |> Map.get("news")
      |> List.wrap()
      |> Enum.reduce(socket, &apply_upload_news/2)

    {:noreply, socket}
  end

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
         |> mark_saved(gettext("The gallery changed under your hands · fresh order loaded"))}
    end
  end

  def handle_event("gallery_set_date", %{"id" => id, "date" => date}, socket) do
    %{article: article, current_scope: scope} = socket.assigns

    with {:ok, id} <- parse_id(id),
         {:ok, image} <- Gallery.set_date(article.id, id, date, by: scope.user.id) do
      Articles.push_log(
        article,
        scope.user,
        "set the date of #{image.filename} to #{I18n.format_moment(image.gallery_date)}"
      )

      {:reply, %{ok: true}, socket |> assign_gallery() |> mark_saved()}
    else
      {:error, :invalid_date} ->
        {:reply, %{ok: false}, mark_saved(socket, gettext("That date could not be read"))}

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
        {:noreply, mark_saved(socket, gettext("Too late · the picture is gone for good"))}
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
        {:noreply, socket |> assign_article(article) |> mark_saved()}

      true ->
        {:ok, article} = Articles.update_settings(article, %{preview_path: path})
        Articles.push_log(article, scope.user, "chose #{Path.basename(path)} as the preview")
        {:noreply, socket |> assign_article(article) |> mark_saved()}
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

  defp gone_note, do: gettext("That tile was deleted a moment ago")

  defp moved_note(socket, meta) do
    name =
      case Accounts.get_user(meta.by) do
        nil -> gettext("Someone")
        user -> admin_name(user)
      end

    file =
      case Enum.find(socket.assigns.gallery, &(&1.id == meta.image_id)) do
        nil -> "a picture"
        image -> image.filename
      end

    "#{name} moved #{file}."
  end

  # Two things can make a publish worth a question, and one dialog asks
  # both at once: somebody else is writing in it this second, and the
  # mail is about to go to people who cannot be unsent. Neither of them
  # true is the common case, and then the click is the whole step.
  defp ask_publish(socket, choice) do
    %{article: article, editing: editing} = socket.assigns
    plan = Publishing.plan(article, choice)

    busy =
      case Editing.who_holds(article.id, self()) do
        {:held, holder} -> unless Editing.holds?(editing), do: holder_name(holder)
        _free_or_mine -> nil
      end

    if is_nil(busy) and plan.recipients == 0 do
      publish_with(socket, plan)
    else
      assign(socket, :dialog, publish_dialog(busy, plan))
    end
  end

  defp publish_dialog(busy, %Publishing.Plan{recipients: readers, choice: choice}) do
    %{
      id: "publish-anyway",
      title:
        if(readers > 0,
          do: gettext("Publish and email %{count} subscribers?", count: readers),
          else: gettext("%{name} is editing this entry right now", name: busy)
        ),
      body:
        Enum.reject(
          [
            busy &&
              gettext("%{name} is writing in it this second, and it goes out as it stands.",
                name: busy
              ),
            readers > 0 &&
              ngettext(
                "One confirmed subscriber gets a mail with the title and the first paragraph. It goes out once and cannot be called back.",
                "%{count} confirmed subscribers get a mail with the title and the first paragraph. It goes out once and cannot be called back.",
                readers,
                count: readers
              ),
            readers == 0 && gettext("Publish it anyway, as it stands this second?")
          ],
          &(&1 in [nil, false])
        ),
      ok: if(readers > 0, do: gettext("Publish and send"), else: gettext("Publish anyway")),
      event: "do_publish",
      value: to_string(choice)
    }
  end

  defp publish_with(socket, %Publishing.Plan{} = plan) do
    %{article: article, current_scope: scope} = socket.assigns

    case Publishing.run(article, scope.user, plan) do
      {:ok, article} ->
        publish_done(socket, article)

      {:error, _changeset} ->
        mark_saved(socket, gettext("That address is taken by another entry"))
    end
  end

  # The dialog carried the choice back, so the plan is worked out again
  # from the entry as it stands this second: the click acts on what is
  # there now, not on what was there when the question was drawn.
  defp publish_with(socket, choice) when is_atom(choice) do
    publish_with(socket, Publishing.plan(socket.assigns.article, choice))
  end

  # One word for what happened, and the mail is part of it now: the
  # click decided it, so the click answers for it.
  defp publish_done(socket, article) do
    note =
      cond do
        article.status == "scheduled" and article.notify_on_publish ->
          gettext("Scheduled for %{date} · the mail goes out then", date: article.publish_date)

        article.status == "scheduled" ->
          gettext("Scheduled for %{date} · no mail", date: article.publish_date)

        article.notified_on ->
          gettext("Published · the mail is on its way")

        true ->
          gettext("Published quietly · no mail went out")
      end

    socket
    |> put_article(article)
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

  defp save_title(socket, title) do
    cond do
      not Editing.holds?(socket.assigns.editing) ->
        {:noreply, socket}

      true ->
        case Articles.update_text(socket.assigns.article, %{title: title}) do
          {:ok, article} ->
            Lock.ping(article.id, self())
            {:noreply, socket |> assign_article(article) |> announce_activity() |> mark_saved()}

          {:error, _changeset} ->
            {:noreply,
             mark_saved(socket, gettext("That title is too long; 500 characters is the roof"))}
        end
    end
  end

  # a thumbnail loads the scaled reading, never the full original; an
  # outside address in the words has no rendition and is shown as it is
  defp thumb_url("/uploads/" <> relative), do: Images.url(relative, :thumb)
  defp thumb_url(url), do: String.replace(url, "'", "%27")

  # What a row of the file list shows for a reference: the still of a
  # converted film, the picture itself, or nothing - while ffmpeg is
  # still working, and for an upload that is still running or has
  # stopped, which has no address yet. Then the empty box of the row
  # stands for the file.
  defp media_thumb(_media, nil), do: nil

  defp media_thumb(%{still: still}, _url) when is_binary(still),
    do: thumb_url("/uploads/" <> still)

  defp media_thumb(nil, url), do: thumb_url(url)
  defp media_thumb(_media, _url), do: nil

  # What every video of this text shows and how far it is, in one
  # query: the tiles of the gallery and the references in the words.
  defp media(%{article: article, gallery: gallery}) do
    (Enum.map(gallery, & &1.path) ++ Body.upload_paths(article.body))
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
          # the key is the body's own url for the film, byte for byte;
          # the values are addresses and come from Images
          {"/uploads/#{path}",
           %{
             poster: Images.url(entry.still, :thumb),
             full: Images.url(entry.still, :max),
             film: entry.film && Images.url(entry.film, :original)
           }}
        ]
      else
        []
      end
    end)
    |> Map.new()
  end

  # What the admin area says while ffmpeg is not through with a video.
  defp conversion_note(%{state: :queued}), do: gettext("waiting to be converted")
  defp conversion_note(%{state: :running}), do: gettext("converting")
  defp conversion_note(%{state: :none}), do: gettext("waiting to be converted")
  defp conversion_note(%{state: :failed, error: nil}), do: gettext("the conversion failed")

  defp conversion_note(%{state: :failed, error: reason}),
    do: gettext("the conversion failed: %{reason}", reason: reason)

  defp conversion_note(_media), do: nil

  defp tile_count(gallery) do
    ngettext("1 tile", "%{count} tiles", length(gallery))
  end

  defp preview_candidates(%{article: article, gallery: gallery}) do
    Gallery.preview_candidates(article, Enum.map(gallery, & &1.path))
  end

  defp effective_preview(%{article: article, gallery: gallery}) do
    Gallery.effective_preview(article, Enum.map(gallery, & &1.path))
  end

  defp tile_bg(path) do
    "background-image:url('#{Images.url(path, :thumb)}')"
  end

  ## PubSub and lock messages

  def handle_info({:text_changed, %{id: id} = article}, socket) do
    cond do
      id != socket.assigns.article.id or Editing.holds?(socket.assigns.editing) ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> assign_article(article)
         |> push_event("sync_body", %{text: article.body})}
    end
  end

  def handle_info({:article_changed, %{id: id} = incoming}, socket) do
    if id == socket.assigns.article.id do
      current = socket.assigns.article

      article =
        if Editing.holds?(socket.assigns.editing),
          do: %{incoming | title: current.title, body: current.body},
          else: incoming

      # Another admin may have moved the entry, and the address it left
      # behind belongs on this screen too.
      {:noreply, socket |> put_article(article) |> load_redirects()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:article_deleted, id}, socket) do
    if id == socket.assigns.article.id do
      {:noreply,
       socket
       |> put_flash(:info, gettext("The entry was deleted while you had it open."))
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
      {:noreply, socket |> update(:editing, &Editing.flushing/1) |> push_event("flush_body", %{})}
    else
      Lock.flushed(id)
      {:noreply, socket}
    end
  end

  def handle_info(:flush_fallback, socket) do
    if Editing.flushing?(socket.assigns.editing) do
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
        case Editing.holder(socket.assigns.editing) do
          %{user_id: user_id} -> Accounts.get_user(user_id)
          _nobody -> nil
        end

      if displaced, do: Articles.snapshot(article, displaced)
      Articles.push_log(article, scope.user, "took over the entry")

      note =
        if displaced,
          do:
            gettext("You have the entry · %{name} was told",
              name: Accounts.display_name(displaced)
            ),
          else: gettext("You have the entry")

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

  def handle_info({:comments_imported, id}, socket) do
    {:noreply, maybe_reload_comments(socket, id)}
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
    case Editing.who_holds(socket.assigns.article.id, self()) do
      {:held, holder} -> "#{holder_name(holder)} is editing now. Your changes are saved."
      _free_or_mine -> gettext("Your changes are saved.")
    end
  end

  # Autosave settled, snapshot written, transfer free to go ahead.
  defp finish_flush(socket) do
    %{article: article, current_scope: scope} = socket.assigns

    if Editing.flushing?(socket.assigns.editing) do
      Articles.snapshot(article, scope.user)
      Lock.flushed(article.id)
    end

    update(socket, :editing, &Editing.flushed/1)
  end

  defp refresh_lock(socket) do
    %{article: article, current_scope: scope, editing: was} = socket.assigns
    editing = Editing.refresh(was, article.id, scope.user.id, self())

    socket
    |> assign(:editing, editing)
    |> push_event("set_readonly", %{readOnly: Editing.read_only?(editing)})
    |> announce_activity()
  end

  # The two ways an address can be refused, in the words of the note.
  defp slug_error(changeset) do
    case changeset.errors[:slug] do
      {"is an address the site itself uses", _} ->
        gettext("That address belongs to the site itself")

      _ ->
        gettext("That address is taken by another entry")
    end
  end

  ## Saved state

  @note_ms 4600

  # A note has a lifetime of its own. A save that happens inside it
  # says nothing new, and must not take the words away: a refused
  # picture changes the body, and the save that follows would have
  # silenced the line that said why.
  defp mark_saved(socket, note \\ nil) do
    now = System.system_time(:millisecond)
    standing? = is_nil(note) and now < (socket.assigns[:saved_until] || 0)

    socket
    |> assign(:saved_at, now)
    |> then(fn socket ->
      if standing? do
        socket
      else
        socket
        |> assign(:saved_note, note)
        |> assign(:saved_until, if(note, do: now + @note_ms, else: 0))
      end
    end)
  end

  # The suggestions keep their order while the editor is open: a tag
  # another text carries keeps its chip when this one drops it, so one
  # more click puts it back, and new tags join the end of the row.
  # Nothing under the pointer moves while somebody is clicking.
  #
  # A tag no text carries any more is off the blog, so it leaves the
  # row with the text it stood on. Without that, a word typed by
  # mistake would keep a chip until the editor is closed.
  # The entry, as it now stands. Going live, coming back off and a
  # moved date all change what there is to count, and any of them can
  # happen while the Stats tab is open - from this browser or from
  # another admin's. So the numbers come along with the entry.
  defp put_article(socket, article) do
    socket |> assign_article(article) |> load_stats(socket.assigns.tab)
  end

  # The entry, and with it the one question the whole bar hangs on:
  # does the working copy say something the readers have not been given
  # yet? Every path that writes the entry comes through here, so the
  # word in the bar, the main button and the menu can never disagree
  # with the text on the screen.
  defp assign_article(socket, article) do
    socket
    |> assign(:article, article)
    |> assign(:pending, Articles.unpublished_changes?(article))
  end

  # The numbers of this entry, read when the tab is opened. An entry
  # nobody can read has none, and says so instead.
  defp load_stats(socket, "stats") do
    article = socket.assigns.article

    if Visibility.live?(article) do
      assign(socket, :stats, %{
        views: Stats.article_views(article.id),
        days: Stats.by_day(14, article_id: article.id),
        referrers: Stats.referrers(14, article_id: article.id)
      })
    else
      assign(socket, :stats, nil)
    end
  end

  defp load_stats(socket, _tab), do: socket

  defp stats_empty(%{status: "scheduled", publish_date: date}) do
    gettext("No numbers yet. It goes live on %{date}.", date: date)
  end

  defp stats_empty(_article) do
    gettext("No numbers yet. Drafts are invisible to readers, so nothing is counted.")
  end

  # The date the counting started is the day the entry went live.
  defp views_label(%{publish_date: %Date{} = date}),
    do: gettext("views since %{date}", date: date)

  defp views_label(_article), do: gettext("views")

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
      # There is always a door. An entry with a slug wears its own
      # address; one without has none yet, and until then the way in is
      # by id. Both open the same page, and both only for an admin.
      |> assign(
        :public_url,
        Articles.reader_path(assigns.article) || ~p"/preview/#{assigns.article.id}"
      )
      |> assign(:public_title, public_title(assigns.article))
      # One value, read two ways, so the markup below says holds_lock
      # and holder without anybody being able to move them apart.
      |> assign(:holds_lock, Editing.holds?(assigns.editing))
      |> assign(:holder, Editing.holder(assigns.editing))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={Articles.display_title(@article)}
      active="texts"
      others={@others}
    >
      <%!-- The state, said once and in one place. It used to be said
           twice, and three times on a live entry: a pill, a chip and a
           button all carrying the same word. Nothing here is a button,
           so "Draft" and "Publish" stop saying the same thing. --%>
      <:lead>
        <span
          class={["st", if(@pending, do: "pending", else: state_tone(@article.status))]}
          id="stateWord"
        >
          <i aria-hidden="true"></i>
          <%!-- Two words, because this pill shares a phone bar with the
               title of the entry and the publish button. A sentence
               here ran under the button and took the title with it. --%>
          <b>
            {if @pending, do: gettext("Live · draft"), else: status_word(@article.status)}
          </b>
        </span>
      </:lead>

      <:bar>
        <%!-- Somebody else is in this text. The offer that used to
             stand beside this is gone: clicking into the title or the
             body already asks for the takeover. --%>
        <span :if={@holder} class="pres" id="barPres">
          <i aria-hidden="true"></i>
          <span class="w">
            {if own_tab?(@holder, @current_scope),
              do: gettext("another tab of yours is writing"),
              else: gettext("%{name} is writing", name: holder_name(@holder))}
          </span>
        </span>

        <%!-- The save state, and no longer a link with a bare arrow on
             it: the way to the reader's side is the button at the end
             of this bar, or a row of its menu, and it carries a word.
             The clock reading is gone with the link; the exact second
             lives in the tooltip, where a moving number cannot pull at
             the eye. --%>
        <span
          class="saved whitespace-nowrap num save-on"
          id="state"
          phx-hook="SavedTicker"
          data-at={@saved_at}
          data-note={@saved_note}
          data-note-until={@saved_until}
        >
          {gettext("Last saved · just now")}
        </span>
        <%!-- the one save state that needs the eye. LiveView puts the
             class on an element above this one the moment the socket
             drops, so no event and no timer is needed. --%>
        <span class="saved warn whitespace-nowrap save-off" id="stateOffline">
          {gettext("Not saved · offline")}
        </span>

        <%!-- One control, one shape at the right edge in every state.
             A live entry gets View, because looking at it is what you
             want from a text that is already out - unless it is being
             rewritten, and then the one thing worth a click is handing
             the new words to the readers. --%>
        <span
          class={[
            "split",
            if(@article.status == "draft" or @pending, do: "solid", else: "calm")
          ]}
          id="stateBtn"
        >
          <%= if @pending do %>
            <button
              class="main"
              id="stateMain"
              phx-click="publish_changes"
              data-flush-body
              title={
                gettext(
                  "Hands the text as it stands to the readers. The day, the address and the state do not move, and no mail goes out."
                )
              }
            >
              {gettext("Publish changes")}
            </button>
          <% end %>
          <%= if Visibility.live?(@article) and not @pending do %>
            <a
              class="main"
              id="stateMain"
              href={@public_url}
              target="_blank"
              rel="noopener"
              title={@public_title}
            >
              {gettext("View")}
            </a>
          <% end %>
          <%= if not Visibility.live?(@article) do %>
            <button
              class="main"
              id="stateMain"
              phx-click="publish"
              data-flush-body
              title={
                gettext(
                  "Publishes the entry now. A future publish date in the settings schedules it instead."
                )
              }
            >
              {if @article.status == "scheduled",
                do: gettext("Publish now"),
                else: gettext("Publish")}
            </button>
          <% end %>
          <span class="div" aria-hidden="true"></span>
          <button
            class="chev"
            id="stateChev"
            phx-click={if @state_menu, do: "close_state_menu", else: "open_state_menu"}
            aria-haspopup="true"
            aria-expanded={to_string(@state_menu)}
            aria-label={gettext("More actions for this entry")}
          >
            <.chevron_icon />
          </button>
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
        <%!-- The mail is the one thing here that cannot be taken back,
             so once it has gone the menu says so before it offers
             anything else. --%>
        <p :if={@article.notified_on} class="fact" id="mailSaid">
          {gettext("The subscriber email went out on %{day}.", day: @article.notified_on)}
        </p>

        <%!-- data-flush-body: the editor settles its debounce on the
             mousedown, so the snapshot can never miss the last
             keystrokes. The attribute is the contract; the event name
             stays the server's own business. --%>
        <button class="row" id="saveVersionRow" phx-click="save_version" data-flush-body>
          {gettext("Save version")}
        </button>
        <%!-- While the entry is being rewritten the main button belongs
             to the readers, so the way to the page moves in here. --%>
        <a
          :if={@public_url && (not Visibility.live?(@article) || @pending)}
          class="row"
          id="viewRow"
          href={@public_url}
          target="_blank"
          rel="noopener"
        >
          {gettext("Open the entry")} <.out_icon />
        </a>
        <%!-- The way back out of a rewrite. It is a restore like any
             other, so the words being thrown away are snapshotted
             first and nothing here is ever finally lost. --%>
        <button :if={@pending} class="row" id="discardChangesRow" phx-click="ask_discard">
          {gettext("Discard the changes")}
        </button>

        <%!-- The mail decision is a verb, not a switch on a pane. It
             used to be a checkbox in the article settings, where it
             armed a thing that then happened as a side effect of a
             click somewhere else. --%>
        <%= if @article.status == "draft" do %>
          <button class="row" id="publishQuietRow" phx-click="publish_quietly">
            {gettext("Publish quietly, no mail")}
          </button>
        <% end %>
        <%= if @article.status == "scheduled" do %>
          <button class="row" id="goliveMailRow" phx-click="toggle_notify">
            {if @article.notify_on_publish,
              do: gettext("No mail at go-live"),
              else: gettext("Email subscribers at go-live")}
          </button>
          <button class="row" id="unscheduleRow" phx-click="unpublish">
            {gettext("Unschedule")}
          </button>
        <% end %>
        <%= if Visibility.live?(@article) do %>
          <button class="row" id="unpublishRow" phx-click="unpublish">
            {gettext("Unpublish")}
          </button>
        <% end %>

        <%!-- A copy to keep, or to carry to another site: the entry as
             a folder with its text and its files, in the format the
             import reads. It leaves the entry as it is. --%>
        <a class="row" id="exportRow" href={~p"/admin/texts/#{@article}/export"} download>
          {gettext("Export as a zip")}
        </a>

        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <button class="row far" id="deleteRow" phx-click="ask_delete">
          {gettext("Delete this entry")}
        </button>
      </div>

      <p :if={@saved_note} class="state-live" id="stateLine" role="status" aria-live="polite">
        {@saved_note}
      </p>

      <%!-- The lock banner: the only place that tells the lock story.
           There is no button on it, because clicking into the title or
           the body already asks.

           It stands under the bar and across the whole screen, not in
           a box inside the column of words: it is news about the
           screen, not about the paragraph it would otherwise sit on
           top of.

           Two banners and not one with a switch inside it. They used
           to open the same way, with the same live dot and the same
           name in the same ink, and the only difference was the
           sentence after it, so writing and being watched looked alike
           at a glance. The one that is yours wears the accent the
           admin area uses for what is yours and leads with You, and it
           only appears while somebody is actually reading along: alone
           in a text you need no telling that you are writing it. A
           second window of your own is somebody reading along too, and
           it is what that window says about this one. --%>
      <div :if={@holds_lock && watchers(assigns) != []} class="jbar mine" id="jbar">
        <span class="dot" aria-hidden="true"></span>
        <b>{gettext("You are writing.")}</b>
        <span class="w">
          {ngettext(
            "%{names} reads along and sees it as you type. The title and the body are read-only there until you stop.",
            "%{names} read along and see it as you type. The title and the body are read-only there until you stop.",
            length(watchers(assigns)),
            names: named(watchers(assigns))
          )}
        </span>
      </div>

      <%!-- one running line, not a name column and a text column: a
           second line of it starts at the left edge like the first,
           and nothing is indented under the name --%>
      <div :if={!@holds_lock && @holder} class="jbar theirs" id="jbar">
        <span class="dot" aria-hidden="true"></span>
        <b>
          {if own_tab?(@holder, @current_scope),
            do: gettext("You are writing in another tab."),
            else: gettext("%{name} is writing.", name: holder_name(@holder))}
        </b>
        <span class="w">
          {gettext(
            "The title and the body are read-only for you until they stop. Click into either one to take the entry over."
          )}
        </span>
      </div>

      <%!-- Two columns, one scrollbar each and no third one. The words
           are the page: they scroll with the browser's own bar, however
           long the entry gets. The article settings stand still beside
           them, one screen tall, with a bar of their own that is always
           drawn (.sidecol), so the column never looks like it ends
           where the window does. --%>
      <div class="xl:grid xl:grid-cols-[minmax(0,1fr)_380px] lg:grid lg:grid-cols-[minmax(0,1fr)_320px]">
        <div class="min-w-0" id="textCol">
          <div class="max-w-[680px] mx-auto px-[14px] lg:px-[30px] pt-[22px] lg:pt-[30px] pb-10 lg:pb-[110px]">
            <nav
              class="flex gap-0.5 border-b border-rule mb-6 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
              aria-label={gettext("Entry sections")}
            >
              <button
                :for={
                  {tab, label} <- [
                    {"text", gettext("Text")},
                    {"comments", gettext("Comments")},
                    {"stats", gettext("Stats")},
                    {"log", gettext("Log")},
                    {"versions", gettext("Versions")}
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
                  placeholder={gettext("Title")}
                  aria-label={gettext("Title")}
                  autocomplete="off"
                  phx-debounce="300"
                  readonly={!@holds_lock}
                  phx-click={!@holds_lock && "ask_takeover"}
                />
              </form>
              <%!-- Tab goes from the title to the words, not through
                   nine buttons on the way. The bar stands after the
                   body in the document and is lifted over it by
                   `order`, so it keeps its place on the screen and
                   comes after the writing surface for the keyboard.
                   Nothing is unreachable: the bar is the next stop
                   after the body. --%>
              <div class="flex flex-col">
                <div class={["relative", !@holds_lock && "is-readonly"]} id="bodyWrap">
                  <%!-- the hook replaces the textarea below, and its
                       placeholder and label with it, so the words the
                       writing surface shows arrive on the host --%>
                  <div
                    id="edBodyHost"
                    class="ed-body ed-cm"
                    phx-hook="BodyEd"
                    phx-update="ignore"
                    data-readonly={to_string(!@holds_lock)}
                    data-upload-url={~p"/admin/texts/#{@article.id}/images"}
                    data-max-upload-mb={Texttile.Settings.get(:max_upload_mb)}
                    data-tokens={Jason.encode!(Body.token_templates())}
                    data-picker="#mdImgFile"
                    data-dropzone="#bodyWrap"
                    data-drop-flag="#bodyDropFlag"
                    data-posters={Jason.encode!(poster_map(@media))}
                    data-label={gettext("Body, Markdown")}
                    data-placeholder={
                      gettext(
                        "Write. Markdown works: ## for a heading. Paste an image or drop one here to put it in the text."
                      )
                    }
                  >
                    <textarea
                      class="ed-body"
                      aria-label={gettext("Body, Markdown")}
                      spellcheck="false"
                      placeholder={
                        gettext(
                          "Write. Markdown works: ## for a heading. Paste an image or drop one here to put it in the text."
                        )
                      }
                      readonly={!@holds_lock}
                    >{@article.body}</textarea>
                  </div>
                  <p class="ed-foot" id="edFoot">
                    <span class="flag">
                      <i class="inline-block w-[6px] h-[6px] rounded-full bg-accent"></i>{gettext(
                        "Editing"
                      )}
                    </span>
                    <span id="edFootText">
                      <%= if @holds_lock do %>
                        {gettext("The draft saves as you type.")}
                        <b>{gettext("Save version")}</b>
                        {gettext(
                          "takes a snapshot of the title and the body that you can go back to."
                        )}
                      <% else %>
                        {gettext("The title and the body are read-only right now.")}
                        <b>{gettext("Save version")}</b>
                        {gettext("and the Versions tab still work.")}
                      <% end %>
                    </span>
                  </p>
                  <span class="drop-flag" id="bodyDropFlag" hidden>
                    {gettext("Put the image in the text, where the caret is")}
                  </span>
                </div>
                <.md_bar
                  id="mdBar"
                  class="order-first"
                  readonly={!@holds_lock}
                  note={gettext("Markdown Editor")}
                />
              </div>
              <input
                type="file"
                id="mdImgFile"
                class="sr"
                multiple
                accept="image/*,video/*"
                aria-label={gettext("Put pictures and videos in the text")}
              />

              <%!-- the images in the text: a reading of the body, never
                   a list of its own. An upload that is still running
                   holds its place with a token, and the token becomes
                   the reference when the upload finishes. --%>
              <div class="mt-[34px]">
                <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
                  <span class="text-[13px] font-semibold">
                    {gettext("Pictures and videos in the text")}
                    <span class="note num" id="inlineCount">{inline_count(@article.body)}</span>
                  </span>
                  <span class="sp"></span>
                  <span class="note">{gettext("Paste one into the text, or drop one on it.")}</span>
                </div>
                <div id="inlineImgs">
                  <p :if={Body.refs(@article.body) == []} class="note pt-[10px]">
                    {gettext(
                      "None in this entry yet. Paste a picture or a video into the text, or drop one on it."
                    )}
                  </p>
                  <%= for ref <- Body.refs(@article.body) do %>
                    <% media = ref_media(@media, ref.url) %>
                    <%!-- a picture, or a video ffmpeg is through with:
                         the still stands for it. A video that is not
                         converted yet says where it stands instead. --%>
                    <% thumb = media_thumb(media, ref.url) %>
                    <div :if={ref.kind == :done} class="inrow">
                      <span class="th" style={thumb && "background-image:url('#{thumb}')"}></span>
                      <span class="nm">
                        {ref.file}
                        <span :if={media && conversion_note(media)} class="note">
                          {conversion_note(media)}
                        </span>
                      </span>
                      <span class="raw">{ref.raw}</span>
                    </div>
                    <div :if={ref.kind == :failed} class="inrow">
                      <span class="th"></span>
                      <span class="nm text-julia">{ref.file}</span>
                      <span :if={@holds_lock} class="act">
                        <button class="btn sm" data-img-action="retry" data-img-file={ref.file}>
                          {gettext("Retry")}
                        </button>
                        <button class="btn sm" data-img-action="remove" data-img-file={ref.file}>
                          {gettext("Remove")}
                        </button>
                      </span>
                      <p class="note say max-w-[62ch]">
                        {gettext(
                          "The upload stopped at %{pct}%, so the file never reached the server. The text keeps a marker where the image belongs. Retry sends the same file again. Remove takes the marker out of the text.",
                          pct: @upload_pcts[ref.file] || 0
                        )}
                      </p>
                    </div>
                    <div :if={ref.kind == :running} class="inrow">
                      <span class="th"></span>
                      <span class="nm">
                        {ref.file}
                        <span class="note num">
                          {if (@upload_pcts[ref.file] || 0) == 0,
                            do: gettext("queued"),
                            else: gettext("uploading %{pct}%", pct: @upload_pcts[ref.file])}
                        </span>
                      </span>
                      <span :if={@holds_lock} class="act">
                        <button class="btn sm" data-img-action="cancel" data-img-file={ref.file}>
                          {gettext("Cancel")}
                        </button>
                      </span>
                      <span class="track">
                        <i style={"width:#{@upload_pcts[ref.file] || 0}%"}></i>
                      </span>
                      <p class="note say">
                        {gettext(
                          "The text holds the place. The marker becomes the image when the upload finishes."
                        )}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <div :if={@tab == "comments"} id="tp-comments">
              <p :if={@comments == []} class="note max-w-[62ch]">
                {gettext("No comments yet.")} {comment_rule(@cmt_require)}
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

            <%!-- One value carries the whole panel: there are numbers,
                 or there is the line that says why there are none.
                 Two conditions could disagree, and an entry that goes
                 live while this tab is open would make them. --%>
            <div :if={@tab == "stats"} id="tp-stats">
              <p :if={is_nil(@stats)} class="note" id="tpStatsEmpty">
                {stats_empty(@article)}
              </p>
              <div :if={@stats}>
                <div class="grid grid-cols-1 md:grid-cols-3 border-y border-rule">
                  <div class="fig py-4 md:pr-5">
                    <div class="n" id="tpFigViews">{number(@stats.views)}</div>
                    <div class="l">{views_label(@article)}</div>
                  </div>
                  <div class="fig py-4 md:px-5 border-t border-hair md:border-t-0 md:border-l md:border-l-hair">
                    <div class="n" id="tpFigComments">{length(@comments)}</div>
                    <div class="l">{gettext("comments")}</div>
                  </div>
                  <div class="fig py-4 md:px-5 border-t border-hair md:border-t-0 md:border-l md:border-l-hair">
                    <div class="n" id="tpFigTiles">{length(@gallery)}</div>
                    <div class="l">{gettext("images in the gallery")}</div>
                  </div>
                </div>

                <h2 class="sec-h">{gettext("Views, last 14 days")}</h2>
                <.day_chart id="tpDayChart" days={@stats.days} />

                <h2 class="sec-h">{gettext("Referrers, last 14 days")}</h2>
                <p :if={@stats.referrers == []} class="note" id="tpReferrersEmpty">
                  {gettext("Nothing counted yet, so there is nowhere readers came from.")}
                </p>
                <.referrer_table
                  :if={@stats.referrers != []}
                  id="tpReferrers"
                  rows={@stats.referrers}
                />

                <p class="note mt-[22px]">
                  {gettext(
                    "Counted by this server alone. No cookie, no fingerprint, no third party. The whole blog is on the"
                  )}
                  <.link class="link" navigate={~p"/admin/stats"}>{gettext("Stats screen")}</.link>.
                </p>
              </div>
            </div>

            <div :if={@tab == "log"} id="tp-log">
              <p class="note mb-4">
                {gettext(
                  "Everything that happened to this entry, newest first: your edits, the edits of every other admin, every handover of the entry, and every version anybody saved."
                )}
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
                <b>{gettext("Save version")}</b>
                {gettext(
                  "in the bar saves the current version of the title and the body. Article settings are never versioned, because they are shared and live. Every version below shows what changed against the one before it, and can be restored."
                )}
              </p>
              <div id="versionsList">
                <p :if={@versions == []} class="note">
                  {gettext("No versions yet.")} <b>{gettext("Save version")}</b>
                  {gettext(
                    "in the bar writes the first one, and every one after it shows what changed."
                  )}
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
                    <span class="note num">
                      {gettext("%{count} words", count: word_count(version.body))}
                    </span>
                    <span :if={index == 0} class="note">{gettext("newest")}</span>
                    <%!-- which of them the readers have. On a live entry
                         one version is the site, and the Versions tab is
                         the only screen that can say which. --%>
                    <span
                      :if={@article.live_version_id == version.id && Visibility.live?(@article)}
                      class="note is-live"
                      id={"liveVersion-#{version.id}"}
                    >
                      {gettext("live")}
                    </span>
                    <span class="sp"></span>
                    <button
                      class="btn quiet sm"
                      phx-click="restore_version"
                      phx-value-id={version.id}
                    >
                      {gettext("Restore this version")}
                    </button>
                  </div>
                  <p class="note mt-[6px]">
                    <%= if index + 1 < length(@versions) do %>
                      {gettext("What changed against the version from")} {stamp(
                        Enum.at(@versions, index + 1).inserted_at
                      )}: <span class="dif-add">{gettext("added")}</span>, <span class="dif-del">{gettext("removed")}</span>.
                    <% else %>
                      {gettext("The first version of the entry.")}
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
          aria-label={gettext("Article settings")}
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
            data-upload-url={~p"/admin/texts/#{@article.id}/gallery"}
            data-csrf={Phoenix.Controller.get_csrf_token()}
            data-max-upload-mb={Texttile.Settings.get(:max_upload_mb)}
          >
            <div class="flex items-baseline gap-[10px] flex-wrap pb-[10px] border-b border-rule">
              <span class="text-[13px] font-semibold">
                {gettext("Tiles")} <span class="note num" id="tileCount">{tile_count(@gallery)}</span>
                <span class="note num" id="tileOnWay" phx-update="ignore"></span>
              </span>
              <span class="sp"></span>
              <span class="note">{gettext("Grab a tile to sort it.")}</span>
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
                  data-date={I18n.format_field_moment(image.gallery_date)}
                  data-full={@media[image.path].still && Images.url(@media[image.path].still, :max)}
                  data-video={
                    @media[image.path].film && Images.url(@media[image.path].film, :original)
                  }
                  data-original={Images.url(image.path, :original)}
                  title={"#{image.filename} · #{I18n.format_plain_day(image.gallery_date)}"}
                  style={@media[image.path].still && tile_bg(@media[image.path].still)}
                  role="button"
                  tabindex="0"
                  aria-label={
                    gettext("Tile %{index}, %{file}, grab to sort, tap to see it big",
                      index: index,
                      file: image.filename
                    )
                  }
                >
                  <span class="n">{String.pad_leading("#{index}", 2, "0")}</span>
                  <span :if={@effective_preview == image.path} class="cov">{gettext("preview")}</span>
                  <span :if={@media[image.path].film} class="play-badge" aria-hidden="true"></span>
                  <span :if={conversion_note(@media[image.path])} class="tile-wait">
                    {conversion_note(@media[image.path])}
                  </span>
                  <button
                    type="button"
                    class="tile-del"
                    data-del
                    aria-label={gettext("Delete %{file}", file: image.filename)}
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
                aria-label={gettext("Add pictures and videos")}
              >
                {gettext("+ Add")}
              </button>
            </div>
            <input
              type="file"
              id="tileFiles"
              class="sr"
              multiple
              accept="image/*,video/*"
              aria-label={gettext("Add pictures and videos to the gallery")}
            />
            <span class="drop-flag" id="tileDropFlag" hidden>
              {gettext("Add it to the gallery, at the end")}
            </span>
            <%!-- what the grid has to say for a moment: a tile another
                 admin moved, a file over the roof, an upload that
                 failed. The rule stands over the grid, so this line has
                 nothing to say the rest of the time and is not there. --%>
            <p class="note mt-[10px] transition-colors empty:hidden" id="tileNote"></p>
          </div>

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
              <span class="text-[13px] font-semibold">{gettext("Article settings")}</span>
              <span class="sp"></span>
              <span class="note">{gettext("Every change saves itself.")}</span>
            </div>

            <div class="drow pt-0.5">
              <span class="lab">{gettext("Preview image")}</span>
              <span class="val">
                <div class="flex flex-wrap gap-[6px] items-center" id="coverRow">
                  <%= if @preview_candidates == [] do %>
                    <span class="note">
                      {gettext(
                        "No pictures yet. Once the entry or the gallery has one, pick it here."
                      )}
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
                      aria-label={gettext("Use image %{index} as the preview image", index: index)}
                    >
                    </button>
                    <span :if={length(@preview_candidates) > 8} class="note">
                      {gettext("+%{count} more in the gallery",
                        count: length(@preview_candidates) - 8
                      )}
                    </span>
                  <% end %>
                </div>
                <div class="hint">
                  {gettext("Used in the entries grid, on the front page and in link previews.")}
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">{gettext("Address")}</span>
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
                  <p class="lab">{gettext("Old addresses, still arriving here")}</p>
                  <div :for={old <- @redirects} class="row" id={"oldaddr-#{old.id}"}>
                    <a
                      class="p"
                      href={old.path}
                      target="_blank"
                      rel="noopener"
                      title={gettext("Follows the old address, in a new tab")}
                    >
                      {old.path}
                    </a>
                    <button
                      type="button"
                      class="btn quiet sm"
                      phx-click="delete_redirect"
                      phx-value-id={old.id}
                      aria-label={gettext("Stop answering %{path}", path: old.path)}
                    >
                      {gettext("Delete")}
                    </button>
                  </div>
                </div>
              </span>
            </div>

            <div class="drow gtop">
              <span class="labrow">
                <label class="lab" id="edDateLab" for="edDate">
                  {if @article.status == "scheduled",
                    do: gettext("Goes live"),
                    else: gettext("Publish date")}
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
                  {gettext("Reset")}
                </button>
              </span>
              <span class="val">
                <input type="date" id="edDate" name="publish_date" value={@article.publish_date} />
                <div class="hint" id="edDateHint">{date_hint(@article)}</div>
              </span>
            </div>

            <%!-- who the entry is by. The name is read from the account
                 every time, so it follows a rename. The entry moves to
                 another account here; it never moves to nobody. An
                 account that was deleted is offered too, marked: it
                 wrote entries, and an attribution that belongs to
                 somebody who has left is one an admin may make. --%>
            <div class="drow gtop">
              <label class="lab" for="edAuthor">{gettext("Author")}</label>
              <span class="val">
                <select id="edAuthor" name="user_id">
                  <%!-- an entry whose account has gone stands without a
                       name until somebody names an admin here. --%>
                  <option :if={is_nil(@article.user_id)} value="" selected disabled>
                    {gettext("The account has gone")}
                  </option>
                  <option
                    :for={account <- @accounts}
                    value={account.id}
                    selected={@article.user_id == account.id}
                  >
                    {admin_name(account)}
                  </option>
                </select>
              </span>
            </div>

            <div class="drow gtop">
              <span class="lab">{gettext("Type")}</span>
              <span class="val">
                <label class="opt">
                  <input
                    type="radio"
                    name="type"
                    value="post"
                    checked={@article.type == "post"}
                  />
                  <span>
                    {gettext("Blog post")}<span class="note">{gettext(
                      "Listed on the front page and in the feed, has tags, can email subscribers."
                    )}</span>
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
                    {gettext("Page")}<span class="note">{gettext(
                      "Standalone Page, like About or Imprint. Appears in the site menu sorted by publish date, never in the feed."
                    )}</span>
                  </span>
                </label>
              </span>
            </div>

            <div :if={@article.type != "page"} class="drow" id="fieldTags">
              <span class="lab">{gettext("Tags")}</span>
              <span class="val">
                <%!-- the field completes itself out of the tags the
                     blog already carries; the hook owns the list it
                     drops under the field.

                     A half-written word is no tag, so the field waits:
                     it hands the row over when it loses the focus, and
                     the hook hands it over earlier the moment a comma
                     or the Enter key closes a word. --%>
                <input
                  type="text"
                  id="edTags"
                  name="tags"
                  value={@article.tags}
                  aria-label={gettext("Tags")}
                  phx-debounce="blur"
                  phx-hook=".TagType"
                  data-tags={Enum.join(@known_tags, "\n")}
                  data-new={gettext("new")}
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
                      this.fresh = null
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

                    // the tags already closed by a comma. The word being
                    // written is not one of them: counting it in made
                    // the field hide the very word under the caret, so
                    // a new tag never got a row of its own.
                    written() {
                      return this.parts().head.split(",").map(t => t.trim().toLowerCase()).filter(Boolean)
                    },

                    refresh() {
                      const {word} = this.parts()
                      const term = word.toLowerCase()
                      if (!term) return this.close()

                      const taken = this.written()
                      const known = this.known()
                      const hits = known.filter(
                        tag => tag.includes(term) && !taken.includes(tag)
                      )
                      // what the word starts, before what it only touches
                      hits.sort((a, b) => a.startsWith(term) === b.startsWith(term) ? 0 : a.startsWith(term) ? -1 : 1)

                      // A word the blog does not carry yet is a tag as
                      // much as any other, and the menu is where a tag
                      // is confirmed. Without a row of its own the new
                      // word was the one thing here Enter could not
                      // finish, and a field that answers every word but
                      // yours reads as a field that is not listening.
                      this.fresh = known.some(tag => tag.toLowerCase() === term) || taken.includes(term)
                        ? null
                        : word.trim()

                      this.matches = hits.slice(0, this.fresh ? MAX - 1 : MAX)
                      if (this.fresh) this.matches.push(this.fresh)
                      if (!this.matches.length) return this.close()

                      this.at = 0
                      this.paint()
                      this.open()
                    },

                    paint() {
                      const label = this.el.dataset.new || "new"
                      this.menu.replaceChildren(...this.matches.map((tag, i) => {
                        const row = document.createElement("li")
                        row.dataset.tag = tag
                        row.textContent = tag
                        row.setAttribute("role", "option")
                        row.setAttribute("aria-selected", i === this.at ? "true" : "false")
                        if (i === this.at) row.classList.add("on")
                        if (this.fresh && tag === this.fresh) {
                          row.classList.add("fresh")
                          const mark = document.createElement("i")
                          mark.textContent = label
                          row.appendChild(mark)
                        }
                        return row
                      }))
                    },

                    // Under the field, or over it when the field stands
                    // near the bottom edge. The side column scrolls, so
                    // the field ends up down there often, and a menu
                    // that always hung below it hung off the screen:
                    // the word you were writing had a row nobody saw.
                    place() {
                      const r = this.el.getBoundingClientRect()
                      const gap = 4, edge = 8, cap = 240
                      const below = window.innerHeight - r.bottom - gap - edge
                      const above = r.top - gap - edge
                      const want = Math.min(this.menu.scrollHeight, cap)

                      this.menu.style.left = `${r.left}px`
                      this.menu.style.width = `${r.width}px`

                      if (want > below && above > below) {
                        const h = Math.max(80, Math.min(want, Math.round(above)))
                        this.menu.style.maxHeight = `${h}px`
                        this.menu.style.top = `${Math.round(r.top - gap - h)}px`
                      } else {
                        this.menu.style.maxHeight = `${Math.max(80, Math.min(cap, Math.round(below)))}px`
                        this.menu.style.top = `${r.bottom + gap}px`
                      }
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
                      this.fresh = null
                    },

                    key(e) {
                      // Enter finishes the word wherever it stands: the
                      // row under the marker if the menu is up, and
                      // otherwise the letters themselves. A comma used
                      // to be the only way to close a tag, which is a
                      // thing you have to be told.
                      if (e.key === "Enter") {
                        const pick = this.menu.hidden || this.at < 0
                          ? this.parts().word.trim()
                          : this.matches[this.at]
                        if (!pick) return
                        e.preventDefault()
                        this.accept(pick)
                        return
                      }

                      if (this.menu.hidden) return
                      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                        e.preventDefault()
                        const step = e.key === "ArrowDown" ? 1 : -1
                        this.at = (this.at + step + this.matches.length) % this.matches.length
                        this.paint()
                      } else if (e.key === "Tab") {
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
              <span class="lab">{gettext("Comments")}</span>
              <span class="val">
                <label class="opt">
                  <input type="hidden" name="allow_comments" value="false" />
                  <input
                    type="checkbox"
                    id="optComments"
                    name="allow_comments"
                    value="true"
                    checked={@article.allow_comments}
                  /> <span>{gettext("Allow comments")}</span>
                </label>
                <%!-- The mail used to be a switch here, armed on a pane
                     and fired by a click at the other end of the
                     screen. It is a verb in the publish menu now, so
                     the step that cannot be taken back is the step you
                     ask for. What is left here is the one fact this
                     pane still owes: whether this kind of entry mails
                     anybody at all. --%>
                <span id="notifyOpt">
                  <span :if={@article.type == "page"} class="note">
                    {gettext("Pages never email anyone.")}
                  </span>
                  <span :if={@article.type != "page"} class="note">{notify_note(@article)}</span>
                </span>
              </span>
            </div>
          </form>

          <%!-- last in the column: the lines you hand on are the last
               thing you want, after the entry is what it should be --%>
          <.share_block article={@article} />
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
    <%!-- One more group of the pane and nothing more: the same group
         name as Comments above it, no rule of its own, and Copy where
         every other quiet word of this column stands, at the right end
         of the name's row. It used to wear a heading with a rule under
         it, which read as a second screen beginning inside the pane. --%>
    <div
      :if={@show_password? or @share_text}
      class="drow gtop"
      id="shareBlock"
      phx-hook="CopyOut"
    >
      <span class="labrow">
        <span class="lab">{gettext("Share")}</span>
        <%!-- the button says what it did; a word beside it would push
             the button itself out of the way. `CopyOut` wires it, and
             Settings hands over the backup token with the same hook. --%>
        <button :if={@share_text} type="button" class="link" id="copyShare" data-copy>
          {gettext("Copy")}
        </button>
      </span>

      <%!-- the lines read like every other value in this column: the
           same size, the same ink, no box of its own and no bar down
           its side. It grows to what it holds, so nothing scrolls. --%>
      <div :if={@share_text}>
        <span class="val">
          <textarea
            id="shareLines"
            class="sharelines"
            rows={length(String.split(@share_text, "\n"))}
            readonly
            spellcheck="false"
            aria-label={gettext("The lines to pass on")}
          >{@share_text}</textarea>
        </span>
      </div>

      <%!-- Before an entry is live there are no lines to pass on, and
           then this is the one place the access word stands. --%>
      <div :if={!@share_text && @show_password?} id="sharePassword">
        <span class="lab block pt-1">{gettext("Blog password")}</span>
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
    </div>
    """
  end

  # The lines a writer hands on: the title, the address, and the word
  # the blog asks for. Nil while the text has no address of its own,
  # which is every text that is not live yet.
  defp password_hint(true = _protected?, _password) do
    gettext(
      "The whole blog waits behind this one word, this entry with it. Settings > Access is where it changes."
    )
  end

  defp password_hint(false, _password) do
    gettext(
      "The blog is open right now, so nobody is asked for this word. Settings > Access turns the gate on."
    )
  end

  defp share_text(article, password) do
    if Visibility.live?(article), do: live_share_text(article, password)
  end

  defp live_share_text(article, password) do
    case Articles.public_path(article) do
      nil ->
        nil

      path ->
        head =
          gettext("New on %{site}: ", site: Texttile.Settings.site_title()) <>
            Articles.display_title(article) <> "\n" <> TexttileWeb.Endpoint.url() <> path

        case password do
          word when is_binary(word) and word != "" ->
            head <> "\n" <> gettext("The blog password is: ") <> word

          _ ->
            head
        end
    end
  end

  # What the door to the reader's side promises, in the words of the
  # state it opens: a live entry is the page everybody reads, and one
  # that is not live yet is that page for the admins alone.
  defp public_title(article) do
    if Visibility.live?(article) do
      gettext("Opens the entry on the public site, in a new tab")
    else
      gettext(
        "Opens the entry as it was last saved, in a new tab. Only somebody signed in can open this address."
      )
    end
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

  defp stamp(datetime), do: I18n.format_moment(datetime)

  defp apply_upload_news(item, socket) do
    %{article: article, current_scope: scope, editing: editing} = socket.assigns

    case UploadNews.read(item) do
      nil ->
        socket

      %{needs_lock: true} when not holding(editing) ->
        socket

      told ->
        if told.log, do: Articles.push_log(article, scope.user, told.log)
        if told.note, do: mark_saved(socket, told.note), else: socket
    end
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

      n ->
        ngettext(
          "1 comment is still out of the entry: that reader has not followed the confirmation link yet.",
          "%{count} comments are still out of the entry: those readers have not followed the confirmation link yet.",
          n
        )
    end
  end

  # The account behind the lock may have been deleted while it held
  # the text; the banner still needs a word for the person.
  # Opening a text never takes it off anybody now, your own other tab
  # included, so the screen has to be able to say that instead of
  # naming you as if you were somebody else.
  defp own_tab?(%{user_id: user_id}, %{user: %{id: user_id}}), do: true
  defp own_tab?(_holder, _scope), do: false

  defp holder_name(%{user_id: user_id}) do
    case Accounts.get_user(user_id) do
      nil -> gettext("A deleted account")
      user -> admin_name(user)
    end
  end

  defp author_name(%{user: nil}), do: "—"
  defp author_name(%{user: user}), do: admin_name(user)

  defp log_line(%{user: nil, text: text}), do: text
  defp log_line(%{user: user, text: text}), do: "#{admin_name(user)} #{text}"

  # Who else has this text open right now, by name; read from the
  # admin presence the wordmark menu already carries.
  defp reading_along(others, article) do
    for person <- others,
        Enum.any?(person.sessions, &(&1.text_id == article.id)),
        uniq: true,
        do: person.name
  end

  defp named(watchers), do: Enum.join(watchers, ", ")

  # Everybody who has this text open besides the tab asking. Other
  # people by name, and your own other windows as what they are: the
  # window over there says "You are writing in another tab", so this
  # one owes the same fact from the other side.
  #
  # A name is written the way its owner writes it and is never touched
  # here. The phrase for your own tabs is the one thing that needs a
  # capital, and only where it opens the sentence on its own.
  defp watchers(%{others: others, article: article, own_tabs: own_tabs}) do
    names = reading_along(others, article)
    mine = Enum.count(own_tabs, &(&1.text_id == article.id))

    cond do
      mine == 0 ->
        names

      names == [] ->
        [ngettext("Another tab of yours", "%{count} other tabs of yours", mine, count: mine)]

      true ->
        names ++
          [ngettext("another tab of yours", "%{count} other tabs of yours", mine, count: mine)]
    end
  end

  defp inline_count(body) do
    refs = Body.refs(body)
    done = Enum.count(refs, &(&1.kind == :done))
    running = Enum.count(refs, &(&1.kind == :running))
    failed = Enum.count(refs, &(&1.kind == :failed))

    ngettext("1 file", "%{count} files", done) <>
      if(running > 0, do: " · " <> gettext("%{count} on the way", count: running), else: "") <>
      if(failed > 0, do: " · " <> gettext("%{count} failed", count: failed), else: "")
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

  defp date_hint(%{status: "draft"}),
    do: gettext("Empty means whenever you publish. A future date schedules the entry.")

  # The date says what the date does, and nothing about the mail: the
  # mail has one owner on this pane, the group below, and while this
  # line also promised it the two could contradict each other on the
  # same screen.
  defp date_hint(%{status: "scheduled"} = article) do
    if article.publish_date,
      do: gettext("Scheduled. It goes live on %{date}.", date: article.publish_date),
      else: gettext("Pick the day it goes live.")
  end

  defp date_hint(article) do
    if article.publish_date,
      do:
        gettext(
          "Live since %{date}. A future date changes it to unpublished until the date.",
          date: article.publish_date
        ),
      else: gettext("Pick the day it went live. An empty field makes the entry a draft again.")
  end

  defp slug_hint(%{status: "draft"}), do: gettext("Free to change while the entry is a draft.")

  defp slug_hint(article) do
    gettext("%{address} is live; changing it breaks old links.",
      address: TexttileWeb.Endpoint.host() <> Articles.public_path(article)
    )
  end

  # The stamp outranks the status: a text that carried its email out
  # once never sends it again, whatever state it stands in now.
  # What this pane still says about the mail. The decision is a verb in
  # the publish menu; this is the standing fact beside it, and it never
  # asks anybody to tick anything.
  defp notify_note(%{notified_on: %Date{} = day}),
    do:
      gettext(
        "The subscriber email for this entry went out on %{day}. It goes out once; publishing again does not send it again.",
        day: day
      )

  defp notify_note(%{status: "scheduled", notify_on_publish: true} = article),
    do:
      gettext("Goes out to the confirmed subscribers when this goes live on %{date}.",
        date: article.publish_date
      )

  defp notify_note(%{status: "scheduled"} = article),
    do: gettext("No email will go out on %{date}.", date: article.publish_date)

  defp notify_note(%{status: "draft"}),
    do:
      gettext(
        "Publish sends one plain email with the title and the first paragraph to the confirmed subscribers. Publish quietly sends none."
      )

  defp notify_note(_article),
    do:
      gettext(
        "No email went out for this entry. The email goes out only at the moment an entry goes live."
      )

  # The dot beside the state word: hollow while nothing is out,
  # outlined once a date stands, filled once a reader can reach it.
  defp state_tone("published"), do: "live"
  defp state_tone("scheduled"), do: "sched"
  defp state_tone(_status), do: "draft"
end
