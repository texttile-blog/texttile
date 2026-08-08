defmodule Texttile.ImagesTest do
  use Texttile.DataCase, async: false

  alias Texttile.Images
  alias Texttile.Settings
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  # Writes a real image of the given size below the uploads root.
  defp original(rel, width, height) do
    abs = Path.join(Uploads.root(), rel)
    File.mkdir_p!(Path.dirname(abs))
    {:ok, black} = Vix.Vips.Operation.black(width, height)
    :ok = Vix.Vips.Image.write_to_file(black, abs)
    rel
  end

  defp size_of(rel) do
    {:ok, image} = Vix.Vips.Image.new_from_file(Path.join(Uploads.root(), rel))
    {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
  end

  describe "rendition/2" do
    test "scales the longer edge down to the limit, keeping the ratio" do
      rel = original("images/wide.jpg", 4000, 2000)

      {:ok, cached} = Images.rendition(rel, 1600)

      assert cached =~ ~r"^cache/"
      assert size_of(cached) == {1600, 800}
    end

    test "the second ask answers from the cache without touching the file" do
      rel = original("images/a.jpg", 4000, 2000)
      {:ok, cached} = Images.rendition(rel, 1600)
      mtime = File.stat!(Path.join(Uploads.root(), cached)).mtime

      {:ok, again} = Images.rendition(rel, 1600)

      assert again == cached
      assert File.stat!(Path.join(Uploads.root(), again)).mtime == mtime
    end

    test "an image already small enough is answered as it is, uncached" do
      rel = original("images/small.jpg", 900, 500)

      {:ok, answer} = Images.rendition(rel, 1600)

      assert answer == rel
      assert Path.join(Uploads.root(), "cache") |> File.ls() == {:error, :enoent}
    end

    test "a new size drops the old cached size of the same image first" do
      rel = original("images/b.jpg", 4000, 2000)
      {:ok, old} = Images.rendition(rel, 1600)

      {:ok, new} = Images.rendition(rel, 800)

      refute File.exists?(Path.join(Uploads.root(), old))
      assert File.exists?(Path.join(Uploads.root(), new))
    end

    test "dropping sizes leaves the renditions of a same-prefixed neighbour alone" do
      rel = original("images/a.jpg", 4000, 2000)
      neighbour = original("images/a-b.jpg", 4000, 2000)
      {:ok, kept} = Images.rendition(neighbour, 1600)

      {:ok, _} = Images.rendition(rel, 800)

      assert File.exists?(Path.join(Uploads.root(), kept))
    end

    test "the admin thumbnail and the reader size live side by side" do
      rel = original("images/side.jpg", 4000, 2000)

      {:ok, thumb} = Images.rendition(rel, 320)
      {:ok, full} = Images.rendition(rel)

      assert File.exists?(Path.join(Uploads.root(), thumb))
      assert File.exists?(Path.join(Uploads.root(), full))
      assert {:ok, ^thumb} = Images.rendition(rel, 320)
      assert {:ok, ^full} = Images.rendition(rel)
    end

    test "a corrupt file with an image extension is an error, not a crash" do
      abs = Path.join(Uploads.root(), "images/broken.jpg")
      File.mkdir_p!(Path.dirname(abs))
      File.write!(abs, "this is not a jpeg")

      assert {:error, _} = Images.rendition("images/broken.jpg", 1600)
    end

    test "without an explicit edge the setting decides" do
      {:ok, _} = Settings.put(:image_max_edge, 1000)
      rel = original("images/c.jpg", 4000, 2000)

      {:ok, cached} = Images.rendition(rel)

      assert size_of(cached) == {1000, 500}
    end

    test "a missing original is an error, not a crash" do
      assert {:error, _} = Images.rendition("images/never-was.jpg", 1600)
    end
  end

  describe "the cache" do
    # Uploads.usage/0 weighs the cache now, and the settings screen
    # reads it there with every other folder of the volume.
    defp cache_bytes do
      Enum.find_value(Uploads.usage(), 0, &if(&1.dir == "cache", do: &1.bytes))
    end

    test "clear_cache/0 empties it and leaves the original" do
      rel = original("images/d.jpg", 4000, 2000)
      {:ok, _} = Images.rendition(rel, 1600)
      assert cache_bytes() > 0

      :ok = Images.clear_cache()

      assert cache_bytes() == 0
      assert File.exists?(Path.join(Uploads.root(), rel))
    end

    test "changing the max edge setting drops the whole cache" do
      rel = original("images/e.jpg", 4000, 2000)
      {:ok, _} = Images.rendition(rel, 1600)

      {:ok, _} = Settings.put(:image_max_edge, 2000)

      assert cache_bytes() == 0
    end
  end
end
