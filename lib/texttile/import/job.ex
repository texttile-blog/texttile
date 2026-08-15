defmodule Texttile.Import.Job do
  @moduledoc """
  The one import at a time. The job holds the whole story of the
  current import - reading the zip, the report, the run, the summary -
  so the page can leave and come back, and a second admin sees the same
  thing. Every turn of the story goes out on the `import` topic as
  `{:import_state, state}`.

  The work itself runs in a task the job watches; the job stays
  answerable throughout.
  """

  use GenServer

  alias Texttile.Import

  @topic "import"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)
  end

  @doc "Where the import stands right now."
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  @doc """
  Takes the uploaded zip and starts the dry run. The file is the job's
  after this call. Refused while an import is running.
  """
  def validate(server \\ __MODULE__, zip_path, name) do
    GenServer.call(server, {:validate, zip_path, name})
  end

  @doc "Imports the report's healthy bundles, as `user`."
  def start_import(server \\ __MODULE__, user) do
    GenServer.call(server, {:start_import, user})
  end

  @doc "Drops the current story and its files; back to the empty page."
  def discard(server \\ __MODULE__), do: GenServer.call(server, :discard)

  ## GenServer

  @impl true
  def init(:ok) do
    {:ok, bare()}
  end

  defp bare do
    %{
      phase: :idle,
      task: nil,
      dir: nil,
      name: nil,
      report: nil,
      summary: nil,
      message: nil,
      done: 0,
      total: 0,
      current: nil,
      step: nil
    }
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, public(state), state}

  # Refused while a dry run or an import is in flight: a second zip
  # would pull the temp folder out from under the running task.
  def handle_call({:validate, zip_path, name}, _from, %{phase: phase} = state)
      when phase not in [:validating, :running] do
    state = clean(state)
    dir = Path.join(Import.workroom(), "texttile-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    job = self()
    note = fn event -> GenServer.cast(job, {:note, event}) end

    task =
      Task.Supervisor.async_nolink(Texttile.Import.TaskSupervisor, fn ->
        result =
          with {:ok, warnings} <- Import.unpack(zip_path, dir) do
            {:ok, Import.validate(dir, note), warnings}
          end

        File.rm(zip_path)
        {:validated, result}
      end)

    {:reply, :ok, announce(%{state | phase: :validating, task: task, dir: dir, name: name})}
  end

  def handle_call({:validate, _zip_path, _name}, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:start_import, user}, _from, %{phase: :report} = state) do
    job = self()
    report = state.report

    task =
      Task.Supervisor.async_nolink(Texttile.Import.TaskSupervisor, fn ->
        summary =
          Import.run(report, user, fn event -> GenServer.cast(job, {:note, event}) end)

        {:finished, summary}
      end)

    total = Enum.count(report.bundles, &(&1.errors == []))

    {:reply, :ok,
     announce(%{state | phase: :running, task: task, done: 0, total: total, current: nil})}
  end

  def handle_call({:start_import, _user}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(:discard, _from, %{phase: :running} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(:discard, _from, state) do
    {:reply, :ok, announce(clean(state))}
  end

  # The fine print of the work in flight, straight onto the page. A
  # note from a task that is no longer the story (the phases moved on)
  # is dropped.
  @impl true
  def handle_cast({:note, {:bundle, name, index, total}}, %{phase: :running} = state) do
    {:noreply, announce(%{state | done: index - 1, total: total, current: name, step: nil})}
  end

  def handle_cast({:note, event}, %{phase: phase} = state)
      when phase in [:validating, :running] do
    {:noreply, announce(%{state | step: step(event)})}
  end

  def handle_cast({:note, _event}, state), do: {:noreply, state}

  defp step({:checking_url, url, index, total}), do: "checking #{url} (#{index} of #{total})"
  defp step({:fetching, source, index, total}), do: "picture #{index} of #{total}: #{source}"
  defp step({:retrying, url, what}), do: "#{url} #{what}; trying again"
  defp step(_event), do: nil

  @impl true
  def handle_info({ref, message}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    state =
      case message do
        {:validated, {:ok, report, warnings}} ->
          report = %{report | warnings: Enum.uniq(warnings ++ report.warnings)}
          %{state | phase: :report, task: nil, report: report, step: nil}

        {:validated, {:error, reason}} ->
          %{clean(state) | phase: :failed, message: reason}

        {:finished, summary} ->
          # the extracted files are spent the moment the run ends
          %{clean(state) | phase: :done, summary: summary, name: state.name}
      end

    {:noreply, announce(state)}
  end

  # The task died instead of answering. Keep the page honest about it.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    {:noreply,
     announce(%{clean(state) | phase: :failed, message: "the import crashed: #{inspect(reason)}"})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Back to a bare state; the extracted folder goes with it.
  defp clean(state) do
    if state.dir, do: File.rm_rf(state.dir)
    bare()
  end

  # What the page may know: everything except the task and the folder.
  defp public(state), do: Map.drop(state, [:task, :dir])

  defp announce(state) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:import_state, public(state)})
    state
  end
end
