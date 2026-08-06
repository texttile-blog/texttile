defmodule TexttileWeb.ImportLive do
  @moduledoc """
  The import page: upload the zip, read the dry-run report, start the
  run, watch it move. The page owns none of it - `Texttile.Import.Job`
  holds the story, this screen only shows the current chapter and stays
  right when you leave and come back, or when another admin drives.
  """
  use TexttileWeb, :live_view

  alias Texttile.Import.Job

  def mount(_params, _session, socket) do
    if connected?(socket), do: Job.subscribe()

    socket =
      socket
      |> assign(:page_title, "Import")
      |> assign(:job, Job.state())
      |> allow_upload(:zip,
        accept: ~w(.zip),
        max_entries: 1,
        max_file_size: 1_073_741_824,
        auto_upload: true,
        progress: &handle_zip/3
      )

    {:ok, socket}
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("start", _params, socket) do
    case Job.start_import(socket.assigns.current_scope.user) do
      :ok -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "There is no report to import")}
    end
  end

  def handle_event("discard", _params, socket) do
    case Job.discard() do
      :ok -> {:noreply, socket}
      {:error, :busy} -> {:noreply, put_flash(socket, :error, "The import is running")}
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
          {:noreply, put_flash(socket, :error, "An import is running; let it finish first")}
      end
    else
      {:noreply, socket}
    end
  end

  defp importable(report), do: Enum.count(report.bundles, &(&1.errors == []))

  defp texts(1), do: "1 text"
  defp texts(n), do: "#{n} texts"

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Import"
      active="settings"
      others={@others}
    >
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">Import</h1>
        <p class="lead">
          A zip of bundles becomes texts: one folder per text, with Markdown,
          settings and pictures. Pictures may be files in the bundle or URLs;
          the server downloads the URLs itself, so the zip stays small.
          IMPORT.md in the repository is the format, written so a script or
          an AI agent can build the zip from any export.
        </p>

        <%= case @job.phase do %>
          <% :idle -> %>
            <form id="import-upload" phx-change="validate_upload" class="mt-6">
              <label class="btn cursor-pointer relative overflow-hidden">
                Upload the zip
                <.live_file_input
                  upload={@uploads.zip}
                  class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                  aria-label="Upload the zip"
                />
              </label>
              <span :for={entry <- @uploads.zip.entries} class="note ml-2 num">
                {entry.client_name} · {entry.progress}%
              </span>
              <p
                :for={error <- upload_errors(@uploads.zip)}
                class="text-julia text-[13px] mt-2"
              >
                {upload_error_note(error)}
              </p>
              <p class="note mt-3">
                Nothing is written yet: the zip is read and checked first, and
                the report shows what an import would do.
              </p>
            </form>
          <% :validating -> %>
            <p class="mt-6" id="import-validating">
              Reading {@job.name} …
            </p>
          <% :failed -> %>
            <div class="mt-6" id="import-failed">
              <p class="text-julia">{@job.message}</p>
              <p class="mt-4">
                <button class="btn" phx-click="discard" id="import-discard">Start over</button>
              </p>
            </div>
          <% :report -> %>
            <div class="mt-6" id="import-report">
              <h2 class="set-h">The report for {@job.name}</h2>
              <div
                :for={bundle <- @job.report.bundles}
                class="py-[10px] border-b border-hair"
                id={"bundle-#{bundle.name}"}
              >
                <div class="flex items-baseline gap-2 flex-wrap">
                  <b class="text-[14.5px]">{bundle.name}</b>
                  <span :if={bundle.slug} class="note num">/{bundle.slug}</span>
                  <span class="sp"></span>
                  <span :if={bundle.errors == []} class="note">will import</span>
                  <span :if={bundle.errors != []} class="text-julia text-[13px]">
                    will not import
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
                The zip holds no bundle folders.
              </p>
              <p :for={warning <- @job.report.warnings} class="note mt-2">
                {warning}
              </p>
              <p :if={@job.report.hosts != []} class="note mt-2" id="import-hosts">
                Downloads from: {Enum.join(@job.report.hosts, ", ")}. Check
                this list for hosts you do not expect.
              </p>
              <div class="flex gap-2 mt-5">
                <button
                  class="btn solid"
                  id="import-run"
                  phx-click="start"
                  disabled={importable(@job.report) == 0}
                >
                  Import {texts(importable(@job.report))}
                </button>
                <button class="btn quiet" id="import-discard" phx-click="discard">
                  Discard
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
              <p class="note mt-3">
                The import runs on the server; this page may close.
              </p>
            </div>
          <% :done -> %>
            <div class="mt-6" id="import-summary">
              <h2 class="set-h">Imported: {@job.name}</h2>
              <p class="mt-2">
                {@job.summary.created} created · {@job.summary.updated} updated
                <span :if={@job.summary.skipped > 0}>
                  · {@job.summary.skipped} skipped for errors
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
                <button class="btn" phx-click="discard" id="import-done">Done</button>
              </p>
            </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error_note(:too_large), do: "The zip is larger than 1 GB"
  defp upload_error_note(:not_accepted), do: "Only a .zip file works here"
  defp upload_error_note(other), do: "The upload failed (#{other})"
end
