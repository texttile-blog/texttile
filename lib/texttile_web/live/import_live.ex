defmodule TexttileWeb.ImportLive do
  @moduledoc """
  The import page: upload the zip, read the dry-run report, start the
  run, watch it move. The page owns none of it - `Texttile.Import.Job`
  holds the story, this screen only shows the current chapter and stays
  right when you leave and come back, or when another admin drives.
  """
  use TexttileWeb, :live_view

  alias Texttile.Import.Job
  alias Texttile.Settings
  alias Texttile.Uploads

  def mount(_params, _session, socket) do
    if connected?(socket), do: Job.subscribe()

    socket =
      socket
      |> assign(:page_title, gettext("Import"))
      |> assign(:job, Job.state())
      |> assign(:limit_mb, Settings.get(:max_upload_mb))
      |> assign(:free, Uploads.free_bytes())
      # The roof over the zip is the one roof the admin area has:
      # Settings > Storage > Biggest upload. A second number here would
      # be a second thing to find and to raise, and the zip is by far
      # the largest thing this area ever takes. It is read when the
      # page opens, so a new limit holds from the next opening.
      |> allow_upload(:zip,
        accept: ~w(.zip),
        max_entries: 1,
        max_file_size: Settings.max_upload_bytes(),
        auto_upload: true,
        progress: &handle_zip/3
      )

    {:ok, socket}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("start", _params, socket) do
    case Job.start_import(socket.assigns.current_scope.user) do
      :ok ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("There is no report to import"))}
    end
  end

  def handle_event("discard", _params, socket) do
    case Job.discard() do
      :ok -> {:noreply, socket}
      {:error, :busy} -> {:noreply, put_flash(socket, :error, gettext("The import is running"))}
    end
  end

  def handle_info({:import_state, job}, socket) do
    {:noreply, assign(socket, :job, job)}
  end

  defp handle_zip(:zip, entry, socket) do
    if entry.done? do
      path =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          kept =
            Path.join(
              System.tmp_dir!(),
              "texttile-upload-#{System.unique_integer([:positive])}.zip"
            )

          File.cp!(path, kept)
          {:ok, kept}
        end)

      case Job.validate(path, entry.client_name) do
        :ok ->
          {:noreply, socket}

        {:error, :busy} ->
          File.rm(path)

          {:noreply,
           put_flash(socket, :error, gettext("An import is running; let it finish first"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp importable(report), do: Enum.count(report.bundles, &(&1.errors == []))

  defp texts(n), do: ngettext("1 entry", "%{count} entries", n)

  # The address the bundle takes on the site: a post carries its date,
  # a page its slug alone. A bundle without a date lands on today, the
  # day the import runs.
  defp bundle_address(bundle) do
    prefix = Texttile.Articles.public_prefix(%{type: bundle.type, publish_date: bundle.date})
    prefix <> bundle.slug
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Import")}
      active="settings"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">{gettext("Import")}</h1>
        <p class="lead">
          {gettext(
            "A zip of bundles becomes entries: one folder per entry, with Markdown, settings and pictures. Pictures may be files in the bundle or URLs; the server downloads the URLs itself, so the zip stays small."
          )}
          <.import_doc />
          {gettext(
            "in the repository is the format, written so a script or an AI agent can build the zip from any export."
          )}
        </p>

        <%= case @job.phase do %>
          <% :idle -> %>
            <form id="import-upload" phx-change="validate_upload" class="mt-6">
              <label class="btn cursor-pointer relative overflow-hidden">
                {gettext("Upload the zip")}
                <.live_file_input
                  upload={@uploads.zip}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                  aria-label={gettext("Upload the zip")}
                />
              </label>
              <%!-- The percentage belongs to a zip that is travelling.
                   A refused one never travels, and 0% beside its name
                   reads as work in progress. --%>
              <span :for={entry <- @uploads.zip.entries} class="note ml-2 num">
                {entry.client_name}
                <span :if={upload_errors(@uploads.zip, entry) == []}>· {entry.progress}%</span>
              </span>
              <p class="note mt-2" id="import-room">{room_note(@limit_mb, @free)}</p>
              <%!-- Both lists. A zip that is too large or is no zip at
                   all is refused entry by entry, and that error hangs
                   on the entry: reading the upload alone left the
                   refusal unsaid, and the page stood at 0% as though
                   it were still working. --%>
              <p
                :for={error <- upload_errors(@uploads.zip)}
                class="text-julia text-[13px] mt-2"
              >
                {upload_error_note(error, @limit_mb)}
              </p>
              <p
                :for={entry <- @uploads.zip.entries}
                :if={upload_errors(@uploads.zip, entry) != []}
                class="text-julia text-[13px] mt-2"
              >
                <span :for={error <- upload_errors(@uploads.zip, entry)}>
                  {upload_error_note(error, @limit_mb)}
                </span>
              </p>
              <p class="note mt-3">
                {gettext(
                  "Nothing is written yet: the zip is read and checked first, and the report shows what an import would do."
                )}
              </p>
            </form>
          <% :validating -> %>
            <div class="mt-6" id="import-validating">
              <p>{gettext("Reading %{name} …", name: @job.name)}</p>
              <p :if={@job.step} class="note mt-2 num break-all" id="import-step">
                {@job.step}
              </p>
            </div>
          <% :failed -> %>
            <div class="mt-6" id="import-failed">
              <p class="text-julia">{@job.message}</p>
              <p class="mt-4">
                <button class="btn" phx-click="discard" id="import-discard">
                  {gettext("Start over")}
                </button>
              </p>
            </div>
          <% :report -> %>
            <div class="mt-6" id="import-report">
              <h2 class="set-h">{gettext("The report for %{name}", name: @job.name)}</h2>
              <div
                :for={bundle <- @job.report.bundles}
                class="py-[10px] border-b border-hair"
                id={"bundle-#{bundle.name}"}
              >
                <div class="flex items-baseline gap-2 flex-wrap">
                  <b class="text-[14.5px]">{bundle.name}</b>
                  <span :if={bundle.slug} class="note num">{bundle_address(bundle)}</span>
                  <span :if={bundle.comments != []} class="note">
                    {ngettext("1 comment", "%{count} comments", length(bundle.comments))}
                  </span>
                  <span class="sp"></span>
                  <span :if={bundle.errors == []} class="note">{gettext("will import")}</span>
                  <span :if={bundle.errors != []} class="text-julia text-[13px]">
                    {gettext("will not import")}
                  </span>
                </div>
                <p :for={error <- bundle.errors} class="text-julia text-[13px] mt-[3px]">
                  {error}
                </p>
                <p :for={warning <- bundle.warnings} class="note mt-[3px]">
                  {warning}
                </p>
              </div>
              <p :if={@job.report.bundles == []} class="note mt-2">
                {gettext("The zip holds no bundle folders.")}
              </p>
              <p :for={warning <- @job.report.warnings} class="note mt-2">
                {warning}
              </p>
              <p :if={@job.report.hosts != []} class="note mt-2" id="import-hosts">
                {gettext(
                  "Downloads from: %{hosts}. Check this list for hosts you do not expect.",
                  hosts: Enum.join(@job.report.hosts, ", ")
                )}
              </p>
              <div class="flex gap-2 mt-5">
                <button
                  class="btn solid"
                  id="import-run"
                  phx-click="start"
                  disabled={importable(@job.report) == 0}
                >
                  {gettext("Import %{entries}", entries: texts(importable(@job.report)))}
                </button>
                <button class="btn quiet" id="import-discard" phx-click="discard">
                  {gettext("Discard")}
                </button>
              </div>
            </div>
          <% :running -> %>
            <div class="mt-6" id="import-progress">
              <p class="num">
                {@job.done} / {@job.total}<span :if={@job.current}> · {@job.current}</span>
              </p>
              <div class="h-[4px] bg-field rounded mt-2 overflow-hidden">
                <div
                  class="h-full"
                  style={"background:var(--tt-accent); width:#{if @job.total > 0, do: round(@job.done * 100 / @job.total), else: 0}%"}
                >
                </div>
              </div>
              <p :if={@job.step} class="note mt-3 num break-all" id="import-step">
                {@job.step}
              </p>
              <p class="note mt-3">
                {gettext("The import runs on the server; this page may close.")}
              </p>
            </div>
          <% :done -> %>
            <div class="mt-6" id="import-summary">
              <h2 class="set-h">{gettext("Imported: %{name}", name: @job.name)}</h2>
              <p class="mt-2">
                {gettext("%{created} created · %{updated} updated",
                  created: @job.summary.created,
                  updated: @job.summary.updated
                )}
                <span :if={@job.summary.skipped > 0}>
                  · {gettext("%{count} skipped for errors", count: @job.summary.skipped)}
                </span>
              </p>
              <div :if={@job.summary.failed != []} class="mt-3">
                <p
                  :for={{name, message} <- @job.summary.failed}
                  class="text-julia text-[13px] mt-[3px]"
                >
                  {name}: {message}
                </p>
              </div>
              <p class="mt-4">
                <button class="btn" phx-click="discard" id="import-done">{gettext("Done")}</button>
              </p>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # What the page says beside the button: the roof, and the room the
  # volume has left. A zip is the largest thing this area takes, and
  # the server needs the room twice over while it unpacks, so the
  # second number belongs next to the first. `df` says nothing on a
  # system without it, and then the line carries the roof alone.
  defp room_note(limit_mb, nil), do: gettext("Up to %{limit}", limit: mb(limit_mb))

  defp room_note(limit_mb, free) do
    gettext("Up to %{limit} · %{size} free on the server",
      limit: mb(limit_mb),
      size: human_size(free)
    )
  end

  defp mb(limit_mb), do: gettext("%{mb} MB", mb: limit_mb)

  # The roof is named in the message, because the number is a setting
  # now and the person reading this is the person who can raise it.
  defp upload_error_note(:too_large, limit_mb) do
    gettext(
      "The zip is larger than %{limit}. Raise the roof in Settings > Storage > Biggest upload.",
      limit: mb(limit_mb)
    )
  end

  defp upload_error_note(:not_accepted, _limit_mb), do: gettext("Only a .zip file works here")

  defp upload_error_note(other, _limit_mb),
    do: gettext("The upload failed (%{reason})", reason: other)
end
