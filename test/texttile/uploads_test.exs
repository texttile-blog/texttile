defmodule Texttile.UploadsTest do
  use Texttile.DataCase, async: false

  alias Texttile.Settings
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    :ok
  end

  defp svg_file do
    path = Path.join(System.tmp_dir!(), "mark-#{System.unique_integer([:positive])}.svg")
    File.write!(path, "<svg xmlns='http://www.w3.org/2000/svg'/>")
    path
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

    test "refuses anything but svg and png" do
      assert {:error, _} = Uploads.put_site_mark(:logo, svg_file(), "mark.pdf")
    end
  end
end
