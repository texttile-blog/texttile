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

  describe "the addresses a backup client may call from" do
    test "empty is the usual case and is allowed" do
      assert Settings.get(:backup_allowed_ips) == ""
      assert {:ok, ""} = Settings.put(:backup_allowed_ips, "")
    end

    test "one address, several addresses, and spaces around them" do
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "10.0.0.7")
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "10.0.0.7, 192.168.1.4")
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "  10.0.0.7 ,  ::1  ")
      assert {:ok, _} = Settings.put(:backup_allowed_ips, " , ")
    end

    test "IPv6 in every spelling" do
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "::1")
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "2001:0DB8::1")
      assert {:ok, _} = Settings.put(:backup_allowed_ips, "::ffff:10.0.0.7")
    end

    test "a typo is refused and names itself, so nobody is locked out in silence" do
      assert {:error, message} = Settings.put(:backup_allowed_ips, "not an address")
      assert message =~ "no IP address"

      assert {:error, _} = Settings.put(:backup_allowed_ips, "10.0.0.256")
      assert {:error, _} = Settings.put(:backup_allowed_ips, "10.0.0.7/24")
      assert {:error, _} = Settings.put(:backup_allowed_ips, "backup.example.com")

      # One bad entry refuses the whole list: half a list would be a
      # lock the operator did not write.
      assert {:error, _} = Settings.put(:backup_allowed_ips, "10.0.0.7, nonsense")
      assert Settings.get(:backup_allowed_ips) == ""
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
    test "twelve by default, and only a number a list can use" do
      # twelve fills whole rows of cards at two, three and four a row
      assert Settings.get(:posts_per_page) == 12

      assert {:ok, 24} = Settings.put(:posts_per_page, "24")
      assert Settings.get(:posts_per_page) == 24

      assert {:error, _} = Settings.put(:posts_per_page, "0")
      assert {:error, _} = Settings.put(:posts_per_page, "201")
      assert {:error, _} = Settings.put(:posts_per_page, "ten")
      assert Settings.get(:posts_per_page) == 24
    end
  end

  describe "theme_color/0" do
    test "answers the bar of the iris theme, laid over the page" do
      # --tt-bar is rgba(255, 255, 255, .93) over the #f6f3ee page
      assert Settings.theme_color() == "#fefefe"
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

  # The bar of the admin area is the solid violet of the buttons, and
  # the chrome on a phone sits against it.
  describe "admin_theme_color/0" do
    test "answers the solid bar of the iris theme" do
      assert Settings.admin_theme_color() == "#4b2a83"
    end

    test "reads the solid bar out of a stored theme" do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-page: #101010; --tt-barsolid: #204080; }")
      assert Settings.admin_theme_color() == "#204080"
    end

    # A theme stored before the token had a name does not carry it. The
    # bar is painted from the build then, so the chrome takes the same
    # road: a white strip over a violet bar is the seam this closes.
    test "a theme without the token answers the build's own violet" do
      {:ok, _} = Settings.put(:theme_css, ":root { --tt-page: #f6f3ee; --tt-bar: #ffffff; }")

      assert Settings.admin_theme_color() == "#4b2a83"
      assert Settings.theme_color() == "#ffffff"
    end

    test "a translucent solid bar is laid over the page colour" do
      {:ok, _} =
        Settings.put(
          :theme_css,
          ":root { --tt-page: #000000; --tt-barsolid: rgba(255,255,255,.5); }"
        )

      assert Settings.admin_theme_color() == "#808080"
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

    test "refuses a video edge outside 480..3840 or not a number" do
      assert {:error, _} = Settings.put(:video_max_edge, "320")
      assert {:error, _} = Settings.put(:video_max_edge, "4000")
      assert {:error, _} = Settings.put(:video_max_edge, "huge")
      assert {:error, _} = Settings.put(:video_max_edge, "")
      assert Settings.get(:video_max_edge) == 1280

      assert {:ok, 1920} = Settings.put(:video_max_edge, "1920")
      assert Settings.get(:video_max_edge) == 1920
    end

    # The floor is what keeps a typo from locking the blog out of its
    # own uploads: below it a photograph off any phone is refused.
    test "refuses an upload roof outside 10..2048 or not a number" do
      assert {:error, _} = Settings.put(:max_upload_mb, "1")
      assert {:error, _} = Settings.put(:max_upload_mb, "9")
      assert {:error, _} = Settings.put(:max_upload_mb, "2049")
      assert {:error, _} = Settings.put(:max_upload_mb, "lots")
      assert {:error, _} = Settings.put(:max_upload_mb, "")
      assert Settings.get(:max_upload_mb) == 512

      assert {:ok, 10} = Settings.put(:max_upload_mb, "10")
      assert {:ok, 2048} = Settings.put(:max_upload_mb, "2048")
    end

    test "max_upload_bytes/0 is the setting, in bytes" do
      assert Settings.max_upload_bytes() == 512 * 1024 * 1024

      {:ok, _} = Settings.put(:max_upload_mb, 64)
      assert Settings.max_upload_bytes() == 64 * 1024 * 1024
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
