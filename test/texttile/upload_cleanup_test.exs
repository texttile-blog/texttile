defmodule Texttile.UploadCleanupTest do
  use Texttile.DataCase

  alias Texttile.Uploads

  # The cleanup walks the uploads root and removes it folder by folder.
  # `File.rm_rf/1` lists a folder, removes what it listed, and then asks
  # for the folder itself. A rendition request that the browser gave up
  # on writes a moment longer than the test that started it, so a file
  # lands in a folder between the listing and the removal. The system
  # call then answers ENOTEMPTY, Erlang reports it as :eexist, and the
  # bang form raises inside a teardown callback: CI red, the developer
  # machine green, a different test each time.
  describe "clear_uploads/0" do
    @seed_dirs 200
    @writes 400

    test "wins against a writer that is still going" do
      root = Uploads.root()
      seed(root)
      test_process = self()

      writer = spawn(fn -> write_a_while(root, @writes, test_process) end)
      ref = Process.monitor(writer)
      assert_receive :writing, 2_000

      # Clear while the writer works, and once more after it is gone.
      # Neither call may raise.
      clear_while_alive(ref)
      assert clear_uploads() == :ok

      assert File.ls(root) in [{:ok, []}, {:error, :enoent}]
    end

    test "says nothing about a root that is not there" do
      clear_uploads()
      assert clear_uploads() == :ok
    end
  end

  # A tree wide enough that a walk over it takes long enough to lose.
  defp seed(root) do
    for dir <- 1..@seed_dirs do
      path = Path.join(root, "renditions/#{dir}")
      File.mkdir_p!(path)
      for file <- 1..3, do: File.write!(Path.join(path, "#{file}.jpg"), "x")
    end
  end

  # Writes the way a rendition writes: make the folder, then the file.
  # It stops by itself, so the cleanup has something to converge on.
  defp write_a_while(_root, 0, _test_process), do: :ok

  defp write_a_while(root, left, test_process) do
    if left == @writes, do: send(test_process, :writing)

    dir = Path.join(root, "renditions/late-#{left}")

    try do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "a.jpg"), "x")
    rescue
      # The cleanup took the folder out from under this write. That is
      # the same race seen from the other side, and the writer carries on.
      File.Error -> :ok
    end

    write_a_while(root, left - 1, test_process)
  end

  defp clear_while_alive(ref) do
    assert clear_uploads() == :ok

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      0 -> clear_while_alive(ref)
    end
  end
end
