defmodule Texttile.Videos.Queue do
  @moduledoc """
  One conversion at a time, in the order the uploads arrived.

  A video is converted once, and converting is the most expensive
  thing this server does. Running two at once would not finish them
  any sooner and would take the machine away from the readers, so the
  queue holds a single worker. ffmpeg itself keeps to one thread and
  the lowest priority (see `Texttile.Videos`).

  The work runs in a task the queue watches, so the queue stays
  answerable while ffmpeg runs, and a crash costs one video, not the
  line behind it. What the queue is doing goes out on the videos
  topic, which the editor listens to.
  """

  use GenServer

  alias Texttile.Videos

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Puts one stored original in line. Unknown to a queue that is not
  running, which is how the tests convert by hand.
  """
  def push(server \\ __MODULE__, relative) do
    case GenServer.whereis(server) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:push, relative})
    end
  end

  @doc "The path being converted right now, or nil. For the tests."
  def running(server \\ __MODULE__), do: GenServer.call(server, :running)

  ## GenServer

  @impl true
  def init(:ok) do
    {:ok, %{waiting: :queue.new(), running: nil, task: nil}, {:continue, :pick_up}}
  end

  # A server that went down mid-conversion left rows behind. They come
  # back into the line, in the order they were uploaded.
  @impl true
  def handle_continue(:pick_up, state) do
    state =
      Videos.unfinished()
      |> Enum.reduce(state, fn video, state -> enqueue(state, video.path) end)
      |> start_next()

    {:noreply, state}
  end

  @impl true
  def handle_cast({:push, relative}, state) do
    {:noreply, state |> enqueue(relative) |> start_next()}
  end

  @impl true
  def handle_call(:running, _from, state), do: {:reply, state.running, state}

  @impl true
  def handle_info({ref, _result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | running: nil, task: nil} |> start_next()}
  end

  # The task died without finishing. The video is marked failed, so a
  # broken file never keeps the line waiting on a retry.
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    Videos.give_up(state.running, inspect(reason))
    {:noreply, %{state | running: nil, task: nil} |> start_next()}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  ## The line

  defp enqueue(state, relative) do
    if state.running == relative or :queue.member(relative, state.waiting) do
      state
    else
      %{state | waiting: :queue.in(relative, state.waiting)}
    end
  end

  defp start_next(%{running: nil} = state) do
    case :queue.out(state.waiting) do
      {{:value, relative}, waiting} ->
        task =
          Task.Supervisor.async_nolink(Texttile.Videos.TaskSupervisor, fn ->
            case Videos.get(relative) do
              nil -> :ok
              video -> Videos.convert(video)
            end
          end)

        %{state | waiting: waiting, running: relative, task: task}

      {:empty, waiting} ->
        %{state | waiting: waiting}
    end
  end

  defp start_next(state), do: state
end
