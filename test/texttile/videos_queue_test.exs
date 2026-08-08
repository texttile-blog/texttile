defmodule Texttile.VideosQueueTest do
  use Texttile.DataCase, async: false

  import Texttile.VideoFixtures

  alias Texttile.Uploads
  alias Texttile.Videos
  alias Texttile.Videos.Queue

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  defp stored(path) do
    {:ok, relative} = Uploads.put_body_video(path, Path.basename(path))
    relative
  end

  # The conversion runs in a task; the test waits for its result the
  # way a page does, by looking at the state.
  defp until(condition, tries \\ 200) do
    cond do
      condition.() -> :ok
      tries == 0 -> flunk("the conversion never finished")
      true -> Process.sleep(50) && until(condition, tries - 1)
    end
  end

  defp start_queue do
    start_supervised!({Queue, name: :videos_under_test})
    :videos_under_test
  end

  test "converts what is pushed" do
    relative = stored(video_file(320, 240))
    Videos.ensure(relative)
    queue = start_queue()

    Queue.push(queue, relative)

    until(fn -> Videos.get(relative).state == "done" end)
    assert %{mp4: _, poster: _} = Videos.playback(relative)
  end

  test "takes one after the other, and leaves nothing in the line" do
    first = stored(video_file(320, 240))
    second = stored(video_file(320, 240))
    Videos.ensure(first)
    Videos.ensure(second)
    queue = start_queue()

    Queue.push(queue, first)
    Queue.push(queue, second)

    until(fn -> Videos.get(first).state == "done" and Videos.get(second).state == "done" end)
    assert Queue.running(queue) == nil
  end

  test "a failed conversion does not hold up the one behind it" do
    broken = stored(broken_video_file())
    good = stored(video_file(320, 240))
    Videos.ensure(broken)
    Videos.ensure(good)
    queue = start_queue()

    Queue.push(queue, broken)
    Queue.push(queue, good)

    until(fn -> Videos.get(good).state == "done" end)
    assert Videos.get(broken).state == "failed"
  end

  test "the word for a conversion that died without one" do
    relative = stored(video_file(320, 240))
    Videos.ensure(relative)

    # what the queue does when it hears that the work is gone. Called
    # here as the callback it is: a real kill would take the test's
    # database connection with it, and racing a live ffmpeg to the
    # message would only sometimes prove anything.
    task = %Task{ref: make_ref(), owner: self(), pid: self(), mfa: {Videos, :convert, 1}}
    state = %{waiting: :queue.new(), running: relative, task: task}

    {:noreply, after_death} =
      Queue.handle_info({:DOWN, task.ref, :process, self(), :killed}, state)

    assert %{state: "failed", error: ":killed"} = Videos.get(relative)
    assert after_death.running == nil
    assert after_death.task == nil
  end

  test "a conversion that dies does not hold up the one behind it" do
    dies = stored(video_file(1280, 720, seconds: 3))
    next = stored(video_file(320, 240))
    Videos.ensure(dies)
    Videos.ensure(next)
    queue = start_queue()

    Queue.push(queue, dies)
    until(fn -> Queue.running(queue) == dies end)

    server = Process.whereis(queue)
    %{task: %Task{ref: ref}} = :sys.get_state(server)
    send(server, {:DOWN, ref, :process, self(), :killed})
    Queue.push(queue, next)

    # whichever word reaches the queue first, the death or the end of
    # the work, the line moves on
    until(fn -> Videos.get(next).state == "done" end)
    assert Queue.running(queue) == nil
  end

  test "picks up what a stopped server left behind" do
    relative = stored(video_file(320, 240))
    Videos.ensure(relative)

    start_queue()

    until(fn -> Videos.get(relative).state == "done" end)
  end

  test "the same video is never queued twice" do
    relative = stored(video_file(320, 240))
    Videos.ensure(relative)
    queue = start_queue()

    Queue.push(queue, relative)
    Queue.push(queue, relative)
    Queue.push(queue, relative)

    until(fn -> Videos.get(relative).state == "done" end)
    Process.sleep(100)
    assert Queue.running(queue) == nil
  end
end
