defmodule Texttile.SettingsTest do
  use Texttile.DataCase, async: false

  alias Texttile.Settings

  describe "defaults" do
    test "an untouched install answers with the defaults" do
      assert Settings.get(:site_title) == "Texttile"
      assert Settings.get(:site_description) == "Text plus tiles. One text at a time."
      assert Settings.get(:language) == "en"
      assert Settings.get(:about_markdown) == ""
      assert Settings.get(:front_page) == "latest"
      assert Settings.get(:theme_css) == ""
      assert Settings.get(:comments_require_confirmation) == true
      assert Settings.get(:image_max_edge) == 2560
      assert Settings.get(:logo) == nil
      assert Settings.get(:favicon) == nil
    end

    test "all/0 carries every key" do
      all = Settings.all()
      assert all.site_title == "Texttile"
      assert all.image_max_edge == 2560
    end
  end

  describe "put/2" do
    test "stores a value and reads it back typed" do
      assert {:ok, "Two of us"} = Settings.put(:site_title, "Two of us")
      assert Settings.get(:site_title) == "Two of us"

      assert {:ok, 1600} = Settings.put(:image_max_edge, "1600")
      assert Settings.get(:image_max_edge) == 1600

      assert {:ok, false} = Settings.put(:comments_require_confirmation, "false")
      assert Settings.get(:comments_require_confirmation) == false
    end

    test "overwrites an earlier value" do
      {:ok, _} = Settings.put(:site_title, "One")
      {:ok, _} = Settings.put(:site_title, "Two")
      assert Settings.get(:site_title) == "Two"
    end

    test "refuses a language outside the list" do
      assert {:error, _} = Settings.put(:language, "fr")
      assert Settings.get(:language) == "en"
    end

    test "refuses a max edge below 800 or not a number" do
      assert {:error, _} = Settings.put(:image_max_edge, "600")
      assert {:error, _} = Settings.put(:image_max_edge, "huge")
      assert Settings.get(:image_max_edge) == 2560
    end

    test "refuses an unknown front page" do
      assert {:error, _} = Settings.put(:front_page, "page:7")
      assert Settings.get(:front_page) == "latest"
    end

    test "refuses an unknown key" do
      assert {:error, _} = Settings.put(:favourite_animal, "cat")
    end

    test "announces every change on the settings topic" do
      Settings.subscribe()
      {:ok, _} = Settings.put(:site_title, "Announced")
      assert_receive {:setting_changed, :site_title, "Announced"}
    end
  end
end
