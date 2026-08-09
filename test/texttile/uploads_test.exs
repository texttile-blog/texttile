defmodule Texttile.UploadsTest do
  use Texttile.DataCase, async: false

  alias Texttile.Settings
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  describe "under_root/1" do
    test "names the file below the root, from a relative path or from its pieces" do
      assert Uploads.under_root("images/pier.jpg") == "images/pier.jpg"
      assert Uploads.under_root(["images", "pier.jpg"]) == "images/pier.jpg"
    end

    test "a path that climbs out of the root names nothing" do
      assert Uploads.under_root("../secrets.txt") == nil
      assert Uploads.under_root("images/../../secrets.txt") == nil
      assert Uploads.under_root(["images", "..", "..", "secrets.txt"]) == nil
    end
  end

  describe "remove/1" do
    test "takes one file below the root" do
      relative = "images/gone-#{System.unique_integer([:positive])}.txt"
      File.mkdir_p!(Path.dirname(Uploads.absolute(relative)))
      File.write!(Uploads.absolute(relative), "words")

      assert :ok = Uploads.remove(relative)
      refute File.exists?(Uploads.absolute(relative))
    end

    test "leaves a path that climbs out of the root alone" do
      outside = Path.join(System.tmp_dir!(), "keep-#{System.unique_integer([:positive])}.txt")
      File.write!(outside, "words")

      assert :ok = Uploads.remove(Path.relative_to(outside, Uploads.root()))
      assert File.exists?(outside)

      File.rm(outside)
    end
  end

  defp svg_file do
    path = Path.join(System.tmp_dir!(), "mark-#{System.unique_integer([:positive])}.svg")
    File.write!(path, "<svg xmlns='http://www.w3.org/2000/svg'/>")
    path
  end

  defp raster_file(extension, width, height) do
    path = Path.join(System.tmp_dir!(), "mark-#{System.unique_integer([:positive])}#{extension}")
    {:ok, black} = Vix.Vips.Operation.black(width, height)
    :ok = Vix.Vips.Image.write_to_file(black, path)
    path
  end

  defp stored_size(relative) do
    {:ok, image} = Vix.Vips.Image.new_from_file(Path.join(Uploads.root(), relative))
    {Vix.Vips.Image.width(image), Vix.Vips.Image.height(image)}
  end

  describe "site marks" do
    test "stores a logo below the uploads root and remembers it in the settings" do
      {:ok, stored} = Uploads.put_site_mark(:logo, svg_file(), "my mark.svg")

      assert stored =~ ~r"^site/logo-\w+\.svg$"
      assert File.exists?(Path.join(Uploads.root(), stored))
      assert Settings.get(:logo) == stored
      assert Settings.get(:logo_name) == "my mark.svg"
    end

    test "a new upload replaces the file and the setting" do
      {:ok, first} = Uploads.put_site_mark(:favicon, svg_file(), "one.svg")
      {:ok, second} = Uploads.put_site_mark(:favicon, svg_file(), "two.svg")

      refute File.exists?(Path.join(Uploads.root(), first))
      assert File.exists?(Path.join(Uploads.root(), second))
      assert Settings.get(:favicon) == second
    end

    test "reset returns to the default and removes the file" do
      {:ok, stored} = Uploads.put_site_mark(:logo, svg_file(), "one.svg")
      :ok = Uploads.reset_site_mark(:logo)

      refute File.exists?(Path.join(Uploads.root(), stored))
      assert Settings.get(:logo) == nil
      assert Settings.get(:logo_name) == nil
    end

    test "a large raster logo is scaled down to the mark size; pixels stay sharp at 3x" do
      {:ok, stored} = Uploads.put_site_mark(:logo, raster_file(".png", 1200, 600), "big.png")

      assert {256, 128} = stored_size(stored)
    end

    test "a small raster mark is never scaled up" do
      {:ok, stored} = Uploads.put_site_mark(:favicon, raster_file(".png", 40, 40), "small.png")

      assert {40, 40} = stored_size(stored)
    end

    test "jpg and webp are welcome too" do
      {:ok, jpg} = Uploads.put_site_mark(:logo, raster_file(".jpg", 300, 300), "mark.jpg")
      assert {256, 256} = stored_size(jpg)

      {:ok, webp} = Uploads.put_site_mark(:logo, raster_file(".webp", 300, 300), "mark.webp")
      assert {256, 256} = stored_size(webp)
    end

    test "an svg is stored byte for byte, never rasterized" do
      source = svg_file()
      {:ok, stored} = Uploads.put_site_mark(:logo, source, "mark.svg")

      assert File.read!(Path.join(Uploads.root(), stored)) == File.read!(source)
    end

    test "a broken raster file is an error, not a stored file" do
      path = Path.join(System.tmp_dir!(), "broken-#{System.unique_integer([:positive])}.png")
      File.write!(path, "not a png at all")

      assert {:error, _} = Uploads.put_site_mark(:logo, path, "broken.png")
      assert Settings.get(:logo) == nil
    end

    test "refuses anything but svg, png, jpg and webp" do
      assert {:error, _} = Uploads.put_site_mark(:logo, svg_file(), "mark.pdf")
    end
  end

  describe "body images" do
    test "stores the original below images/ under a tagged, readable name" do
      {:ok, stored} = Uploads.put_body_image(raster_file(".jpg", 300, 200), "Pier Lantern.JPG")

      assert stored =~ ~r"^images/pier-lantern-\w+\.jpg$"
      assert File.exists?(Path.join(Uploads.root(), stored))
      assert {300, 200} = stored_size(stored)
    end

    test "refuses anything that is not an image" do
      path = Path.join(System.tmp_dir!(), "note-#{System.unique_integer([:positive])}.txt")
      File.write!(path, "words")
      assert {:error, _} = Uploads.put_body_image(path, "note.txt")
    end

    test "refuses a file that only pretends to be an image" do
      path = Path.join(System.tmp_dir!(), "fake-#{System.unique_integer([:positive])}.png")
      File.write!(path, "not a png")
      assert {:error, _} = Uploads.put_body_image(path, "fake.png")
    end
  end

  describe "what lies on the volume" do
    defp row(usage, dir), do: Enum.find(usage, &(&1.dir == dir))

    test "names every folder of the layout, even before one exists" do
      assert Enum.map(Uploads.usage(), & &1.dir) == ~w(images videos site cache)
      assert Enum.all?(Uploads.usage(), &(&1.files == 0 and &1.bytes == 0))
    end

    test "counts the files and weighs them, folder by folder" do
      {:ok, _} = Uploads.put_body_image(raster_file(".jpg", 300, 200), "pier.jpg")
      {:ok, _} = Uploads.put_body_image(raster_file(".jpg", 120, 90), "lantern.jpg")

      usage = Uploads.usage()

      assert row(usage, "images").files == 2
      assert row(usage, "images").bytes > 0
      assert row(usage, "videos").files == 0
    end

    test "counts what lies in a folder below a folder" do
      nested = Path.join([Uploads.root(), "cache", "deep", "deeper"])
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "rendition.bin"), String.duplicate("x", 1234))

      assert row(Uploads.usage(), "cache") == %{dir: "cache", files: 1, bytes: 1234}
    end

    test "says how much room the volume has left" do
      File.mkdir_p!(Uploads.root())
      free = Uploads.free_bytes()

      # nil is the honest answer where df cannot be asked, and this
      # machine is not that place
      assert is_integer(free) and free > 0
    end

    # The settings screen promises the row is absent instead of wrong
    # where the question cannot be asked, so the nil has to be real and
    # not an exception on its way out.
    test "answers nil instead of raising when df cannot say" do
      root = Application.fetch_env!(:texttile, :uploads_path)
      on_exit(fn -> Application.put_env(:texttile, :uploads_path, root) end)

      Application.put_env(
        :texttile,
        :uploads_path,
        "/no/such/volume-#{System.unique_integer([:positive])}"
      )

      assert Uploads.free_bytes() == nil
      # and the folder rows still answer, with zeros
      assert Enum.all?(Uploads.usage(), &(&1.files == 0 and &1.bytes == 0))
    end
  end
end
