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
      assert Settings.get(:video_max_edge) == 1280
      assert Settings.get(:logo) == nil
      assert Settings.get(:favicon) == nil
    end

    test "site_title/0 falls back to Texttile while the title is blank" do
      assert Settings.site_title() == "Texttile"

      {:ok, _} = Settings.put(:site_title, "   ")
      assert Settings.site_title() == "Texttile"

      {:ok, _} = Settings.put(:site_title, "Breyer Blog")
      assert Settings.site_title() == "Breyer Blog"
    end

    test "all/0 carries every key" do
      all = Settings.all()
      assert all.site_title == "Texttile"
      assert all.image_max_edge == 2560
    end
  end

  describe "site access" do
    test "public by default, with an empty password" do
      assert Settings.get(:site_visibility) == "public"
      assert Settings.get(:site_password) == ""
    end

    test "stores the visibility and the shared password" do
      assert {:ok, "protected"} = Settings.put(:site_visibility, "protected")
      assert {:ok, "sesame"} = Settings.put(:site_password, "sesame")
      assert Settings.get(:site_visibility) == "protected"
      assert Settings.get(:site_password) == "sesame"
    end

    test "only public and protected exist" do
      assert {:error, _} = Settings.put(:site_visibility, "secret")
    end
  end

  describe "posts_per_page" do
    test "ten by default, and only a number a list can use" do
      assert Settings.get(:posts_per_page) == 10

      assert {:ok, 25} = Settings.put(:posts_per_page, "25")
      assert Settings.get(:posts_per_page) == 25

      assert {:error, _} = Settings.put(:posts_per_page, "0")
      assert {:error, _} = Settings.put(:posts_per_page, "201")
      assert {:error, _} = Settings.put(:posts_per_page, "ten")
      assert Settings.get(:posts_per_page) == 25
    end
  end

  describe "theme_color/0" do
    test "answers the bar of the iris theme, laid over the page" do
      # --tt-bar is rgba(255, 255, 255, .93) over the #faf9f7 page
      assert Settings.theme_color() == "#fffffe"
    end

    test "reads the bar out of a stored theme" do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-page: #101010; --tt-bar: #204080; }")
      assert Settings.theme_color() == "#204080"
    end

    test "lays a translucent bar over the page colour" do
      {:ok, _} =
        Settings.put(:theme_css, ":root { --tt-page: #000000; --tt-bar: rgba(255,255,255,.5); }")

      assert Settings.theme_color() == "#808080"
    end

    test "the last declaration of a token wins, the way a browser reads it" do
      {:ok, _} =
        Settings.put(:theme_css, ":root { --tt-bar: #111111; }\n:root { --tt-bar: #222222; }")

      assert Settings.theme_color() == "#222222"
    end

    test "a theme without the tokens falls back instead of failing" do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-ink: #123456; }")
      assert Settings.theme_color() =~ ~r/\A#[0-9a-f]{6}\z/
    end

    test "a bar nobody can read falls back to the page" do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-page: #123456; --tt-bar: chartreuse; }")
      assert Settings.theme_color() == "#123456"
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

    test "refuses a max edge outside 800..10000 or not a number" do
      assert {:error, _} = Settings.put(:image_max_edge, "600")
      assert {:error, _} = Settings.put(:image_max_edge, "10080")
      assert {:error, _} = Settings.put(:image_max_edge, "huge")
      assert {:error, _} = Settings.put(:image_max_edge, "")
      assert Settings.get(:image_max_edge) == 2560
    end

    test "accepts the latest list and a fixed page as the front page" do
      assert {:ok, "page:7"} = Settings.put(:front_page, "page:7")
      assert Settings.get(:front_page) == "page:7"

      assert {:ok, "latest"} = Settings.put(:front_page, "latest")
    end

    test "refuses an unknown front page" do
      assert {:error, _} = Settings.put(:front_page, "sitemap")
      assert {:error, _} = Settings.put(:front_page, "page:")
      assert {:error, _} = Settings.put(:front_page, "page:seven")
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
