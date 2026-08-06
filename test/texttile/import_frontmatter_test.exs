defmodule Texttile.Import.FrontmatterTest do
  use ExUnit.Case, async: true

  alias Texttile.Import.Frontmatter

  defp doc(front), do: "---\n#{front}---\nThe body.\n"

  describe "parse/1" do
    test "reads scalars, inline lists and block lists, and returns the body" do
      text =
        doc("""
        title: Beach days
        date: 2019-06-02
        tags: [travel, sea]
        gallery:
          - gallery/001.jpg
          - https://old.example/a.jpg
        """)

      assert {:ok, front, "The body.\n"} = Frontmatter.parse(text)

      assert front == %{
               "title" => "Beach days",
               "date" => "2019-06-02",
               "tags" => ["travel", "sea"],
               "gallery" => ["gallery/001.jpg", "https://old.example/a.jpg"]
             }
    end

    test "unwraps double quotes and their escapes" do
      text = doc(~s(title: "A \\"quoted\\" name: with a colon"\n))
      assert {:ok, %{"title" => ~s(A "quoted" name: with a colon)}, _} = Frontmatter.parse(text)
    end

    test "quoted items work inside lists" do
      text = doc(~s(tags: ["one, together", plain]\n))
      assert {:ok, %{"tags" => ["one, together", "plain"]}, _} = Frontmatter.parse(text)
    end

    test "empty lines inside the block mean nothing" do
      text = doc("title: A\n\ntags: [b]\n")
      assert {:ok, %{"title" => "A", "tags" => ["b"]}, _} = Frontmatter.parse(text)
    end

    test "the body may be empty" do
      assert {:ok, %{"title" => "A"}, ""} = Frontmatter.parse("---\ntitle: A\n---\n")
    end

    test "a missing opening fence is an error" do
      assert {:error, message} = Frontmatter.parse("title: A\n---\n")
      assert message =~ "---"
    end

    test "a missing closing fence is an error" do
      assert {:error, message} = Frontmatter.parse("---\ntitle: A\n")
      assert message =~ "---"
    end

    test "a line that is neither an entry nor a list item names its number" do
      assert {:error, message} = Frontmatter.parse(doc("title: A\nwhat is this\n"))
      assert message =~ "line 3"
    end

    test "a list item without an open list is an error" do
      assert {:error, message} = Frontmatter.parse(doc("- floating\n"))
      assert message =~ "line 2"
    end

    test "a key without a value and without list items is an error" do
      assert {:error, message} = Frontmatter.parse(doc("gallery:\ntitle: A\n"))
      assert message =~ "gallery"
    end

    test "a duplicate key is an error" do
      assert {:error, message} = Frontmatter.parse(doc("title: A\ntitle: B\n"))
      assert message =~ "title"
    end

    test "an unterminated quote is an error" do
      assert {:error, message} = Frontmatter.parse(doc(~s(title: "open\n)))
      assert message =~ "line 2"
    end

    test "scalar values keep inner colons without quotes" do
      assert {:ok, %{"title" => "a: b"}, _} = Frontmatter.parse(doc("title: a: b\n"))
    end

    test "CRLF line endings parse like LF ones" do
      text = "---\r\ntitle: A\r\ntags: [b]\r\n---\r\nBody\r\n"
      assert {:ok, %{"title" => "A", "tags" => ["b"]}, body} = Frontmatter.parse(text)
      assert body =~ "Body"
    end
  end
end
