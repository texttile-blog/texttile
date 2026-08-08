defmodule Texttile.FeedTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Feed
  alias Texttile.Settings

  @base "https://blog.example"

  describe "public?/0" do
    test "an open blog offers a feed" do
      assert Feed.public?()
    end

    test "a blog behind a password offers none" do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      refute Feed.public?()
    end

    test "protected without a word protects nothing, so the feed stands" do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "")

      assert Feed.public?()
    end

    test "a password that nobody is asked for leaves the feed alone" do
      {:ok, _} = Settings.put(:site_visibility, "public")
      {:ok, _} = Settings.put(:site_password, "sesame")

      assert Feed.public?()
    end
  end

  describe "the channel" do
    test "carries the site's name, description, address and language" do
      {:ok, _} = Settings.put(:site_title, "Harbor & Fog")
      {:ok, _} = Settings.put(:site_description, "Notes from the pier")
      {:ok, _} = Settings.put(:language, "de")

      xml = Feed.rss(@base)

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert xml =~ ~s(<rss version="2.0")
      assert xml =~ "<title>Harbor &amp; Fog</title>"
      assert xml =~ "<description>Notes from the pier</description>"
      assert xml =~ "<link>#{@base}/</link>"
      assert xml =~ "<language>de</language>"
      assert xml =~ ~s(<atom:link href="#{@base}/feed.xml" rel="self")
    end

    test "stands without texts" do
      xml = Feed.rss(@base)

      assert xml =~ "<channel>"
      refute xml =~ "<item>"
    end
  end

  describe "the items" do
    test "hold every published post, newest first, and nothing else" do
      published_post(title: "Old text", publish_date: ~D[2026-01-05])
      published_post(title: "New text", publish_date: ~D[2026-03-01])
      draft_post(title: "Secret draft")
      scheduled_post(title: "Not yet")
      published_page(title: "About the blog")

      xml = Feed.rss(@base)

      assert xml =~ "Old text"
      assert xml =~ "New text"
      refute xml =~ "Secret draft"
      refute xml =~ "Not yet"
      refute xml =~ "About the blog"

      {new_at, _} = :binary.match(xml, "New text")
      {old_at, _} = :binary.match(xml, "Old text")
      assert new_at < old_at
    end

    test "carry title, address, guid, day and tags" do
      article =
        published_post(
          title: "Harbor mornings",
          slug: "harbor-mornings",
          tags: "sea, fog",
          publish_date: ~D[2026-07-02]
        )

      xml = Feed.rss(@base)
      link = @base <> Texttile.Articles.public_path(article)

      assert xml =~ "<title>Harbor mornings</title>"
      assert xml =~ "<link>#{link}</link>"
      assert xml =~ ~s(<guid isPermaLink="true">#{link}</guid>)
      assert xml =~ "<pubDate>Thu, 02 Jul 2026 00:00:00 +0000</pubDate>"
      assert xml =~ "<category>sea</category>"
      assert xml =~ "<category>fog</category>"
    end

    test "carry the whole text as HTML, and the lead as the description" do
      published_post(
        title: "Harbor mornings",
        body: "The lead line stands first.\n\n## A heading\n\nAnd **more** words."
      )

      xml = Feed.rss(@base)

      assert xml =~ "<description>The lead line stands first.</description>"
      assert xml =~ "&lt;h2&gt;A heading&lt;/h2&gt;"
      assert xml =~ "&lt;strong&gt;more&lt;/strong&gt;"
      assert xml =~ "<content:encoded>"
    end

    test "turn the addresses inside a text absolute" do
      published_post(
        title: "With a picture",
        body: "![A pier](/uploads/pier.jpg)\n\nAnd [the archive](/tags/sea) beside it."
      )

      xml = Feed.rss(@base)

      assert xml =~ "src=&quot;#{@base}/renditions/1320/pier.jpg&quot;"
      assert xml =~ "href=&quot;#{@base}/tags/sea&quot;"
      refute xml =~ "src=&quot;/uploads"
      refute xml =~ "href=&quot;/tags"
    end

    test "a film goes as its poster, with the way to the film behind it" do
      {:ok, relative} =
        Texttile.Uploads.put_body_video(
          Texttile.VideoFixtures.video_file(320, 240),
          "Harbour.mov"
        )

      {:ok, video} = Texttile.Videos.convert(Texttile.Videos.ensure(relative))

      published_post(title: "With a film", body: "![Harbour](/uploads/#{relative})")

      xml = Feed.rss(@base)

      # no feed reader plays a video tag, and a rendition of a film is
      # nothing at all
      assert xml =~ "src=&quot;#{@base}/renditions/1320/#{video.poster_path}&quot;"
      assert xml =~ "href=&quot;#{@base}/uploads/#{video.mp4_path}&quot;"
      refute xml =~ "renditions/1320/#{relative}"
      refute xml =~ "&lt;video"
    end

    test "a film that is still converting goes as a plain link" do
      {:ok, relative} =
        Texttile.Uploads.put_body_video(
          Texttile.VideoFixtures.video_file(320, 240),
          "Harbour.mov"
        )

      Texttile.Videos.ensure(relative)
      published_post(title: "With a film", body: "![Harbour](/uploads/#{relative})")

      xml = Feed.rss(@base)

      assert xml =~ "href=&quot;#{@base}/uploads/#{relative}&quot;"
      refute xml =~ "renditions/1320/#{relative}"
    end

    test "leave an address that is already absolute alone" do
      published_post(
        title: "Elsewhere",
        body: "[Another blog](https://elsewhere.example/text) and nothing local."
      )

      xml = Feed.rss(@base)

      assert xml =~ "href=&quot;https://elsewhere.example/text&quot;"
      refute xml =~ "#{@base}https://"
    end

    test "leave out a text that has no address of its own" do
      published_post(title: "Standing text", slug: "standing-text")
      homeless = published_post(title: "Homeless text")
      {:ok, _} = Articles.update_settings(homeless, %{"slug" => ""})

      xml = Feed.rss(@base)

      assert xml =~ "Standing text"
      refute xml =~ "Homeless text"
    end

    test "escape what XML cannot carry" do
      published_post(title: "Fish & <chips>", body: "Salt & pepper.")

      xml = Feed.rss(@base)

      assert xml =~ "<title>Fish &amp; &lt;chips&gt;</title>"
      refute xml =~ "<title>Fish & <chips></title>"
    end

    test "drop the characters XML has no place for" do
      # what a paste out of a PDF or a word processor carries along
      published_post(
        title: "Pasted in" <> <<11>>,
        body: "A vertical tab" <> <<11>> <> ", a form feed" <> <<12>> <> ", and a real\ttab."
      )

      xml = Feed.rss(@base)

      refute String.contains?(xml, <<11>>)
      refute String.contains?(xml, <<12>>)
      assert String.contains?(xml, "\t")
      assert {_document, _rest} = :xmerl_scan.string(String.to_charlist(xml))
    end

    test "leave a protocol-relative address alone" do
      published_post(title: "Elsewhere", body: ~s(<img src="//cdn.example/x.jpg">))

      xml = Feed.rss(@base)

      refute xml =~ "#{@base}//cdn.example"
    end
  end

  describe "the whole document" do
    test "parses, and says when it was last built" do
      published_post(title: "Old text", publish_date: ~D[2026-01-05])
      published_post(title: "New text", publish_date: ~D[2026-03-01])

      xml = Feed.rss(@base)

      assert xml =~ "<lastBuildDate>Sun, 01 Mar 2026 00:00:00 +0000</lastBuildDate>"
      assert {_document, _rest} = :xmerl_scan.string(String.to_charlist(xml))
    end

    test "an empty blog says nothing about a last build" do
      refute Feed.rss(@base) =~ "lastBuildDate"
    end
  end
end
