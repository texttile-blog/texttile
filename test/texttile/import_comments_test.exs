defmodule Texttile.Import.CommentsTest do
  use ExUnit.Case, async: true

  alias Texttile.Import.Comments

  @moduletag :tmp_dir

  defp read(dir, yaml) do
    File.write!(Path.join(dir, "comments.yaml"), yaml)
    Comments.read(dir)
  end

  describe "a bundle without the file" do
    test "has no comments and nothing to complain about", %{tmp_dir: dir} do
      assert Comments.read(dir) == {[], []}
    end
  end

  describe "a full file" do
    test "reads every field, keeps the text as written", %{tmp_dir: dir} do
      {comments, errors} =
        read(dir, """
        - author: Christiane
          email: Christiane@Example.org
          website: https://christiane.example
          date: 2026-07-30 22:14
          id: 12
          text: |
            Ihr Lieben, immer wieder!

            Es war ein Fest mit euren Jungs.
        - author: kb
          date: 2026-07-31 09:02:33
          reply_to: 12
          text: |
            Danke euch!
        """)

      assert errors == []
      assert [first, second] = comments

      assert first.author == "Christiane"
      assert first.email == "christiane@example.org"
      assert first.website == "https://christiane.example"
      assert first.at == ~U[2026-07-30 22:14:00Z]
      assert first.id == 12
      assert first.reply_to == nil
      assert first.text == "Ihr Lieben, immer wieder!\n\nEs war ein Fest mit euren Jungs."

      assert second.author == "kb"
      assert second.email == nil
      assert second.website == nil
      assert second.at == ~U[2026-07-31 09:02:33Z]
      assert second.reply_to == 12
      assert second.text == "Danke euch!"
    end

    test "a one line text needs no block", %{tmp_dir: dir} do
      {[comment], []} =
        read(dir, """
        - author: kb
          date: 2026-07-31 09:02
          text: "Kurz und gut: schön."
        """)

      assert comment.text == "Kurz und gut: schön."
    end

    test "empty lines between comments mean nothing", %{tmp_dir: dir} do
      {comments, []} =
        read(dir, """
        - author: A
          date: 2026-07-30 10:00
          text: one

        - author: B
          date: 2026-07-30 11:00
          text: two
        """)

      assert Enum.map(comments, & &1.author) == ["A", "B"]
    end
  end

  describe "the order" do
    test "is by date, oldest first", %{tmp_dir: dir} do
      {comments, []} =
        read(dir, """
        - author: late
          date: 2026-07-31 09:00
          text: b
        - author: early
          date: 2026-07-30 09:00
          text: a
        """)

      assert Enum.map(comments, & &1.author) == ["early", "late"]
    end

    test "puts a reply behind the comment it answers", %{tmp_dir: dir} do
      {comments, []} =
        read(dir, """
        - author: first
          date: 2026-07-01 09:00
          id: 1
          text: a
        - author: second
          date: 2026-07-02 09:00
          id: 2
          text: b
        - author: answer to first
          date: 2026-07-03 09:00
          reply_to: 1
          text: c
        """)

      assert Enum.map(comments, & &1.author) == ["first", "answer to first", "second"]
    end

    test "a reply to a reply follows its own parent", %{tmp_dir: dir} do
      {comments, []} =
        read(dir, """
        - author: first
          date: 2026-07-01 09:00
          id: 1
          text: a
        - author: second
          date: 2026-07-02 09:00
          id: 2
          text: b
        - author: answer
          date: 2026-07-03 09:00
          id: 3
          reply_to: 1
          text: c
        - author: answer to the answer
          date: 2026-07-04 09:00
          reply_to: 3
          text: d
        """)

      assert Enum.map(comments, & &1.author) ==
               ["first", "answer", "answer to the answer", "second"]
    end
  end

  describe "errors" do
    test "a file that is not a list", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "author: kb\n")
      assert error =~ "comments.yaml"
    end

    test "a field before the first comment", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "  author: kb\n- author: kb\n  date: 2026-07-01 09:00\n  text: a\n")

      assert error =~ "line 1"
    end

    test "an unknown field", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  text: a\n  karma: 3\n")

      assert error =~ "karma"
    end

    test "a missing author", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- date: 2026-07-01 09:00\n  text: a\n")
      assert error =~ "author"
    end

    test "a missing text", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- author: kb\n  date: 2026-07-01 09:00\n")
      assert error =~ "text"
    end

    test "a missing date", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- author: kb\n  text: a\n")
      assert error =~ "date"
    end

    test "a date that is not the format", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- author: kb\n  date: 30.07.2026\n  text: a\n")
      assert error =~ "YYYY-MM-DD HH:MM"
    end

    test "an email that is no address", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  email: kb at example\n  text: a\n")

      assert error =~ "email"
    end

    test "a website that is not http", %{tmp_dir: dir} do
      {[], [error]} =
        read(
          dir,
          "- author: kb\n  date: 2026-07-01 09:00\n  website: javascript:alert(1)\n  text: a\n"
        )

      assert error =~ "website"
    end

    test "an id that is not a number", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  id: twelve\n  text: a\n")

      assert error =~ "id"
    end

    test "the same id twice", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, """
        - author: a
          date: 2026-07-01 09:00
          id: 1
          text: a
        - author: b
          date: 2026-07-02 09:00
          id: 1
          text: b
        """)

      assert error =~ "1"
    end

    test "a reply_to that names nothing", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  reply_to: 99\n  text: a\n")

      assert error =~ "99"
    end

    test "replies that answer each other in a circle", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, """
        - author: a
          date: 2026-07-01 09:00
          id: 1
          reply_to: 2
          text: a
        - author: b
          date: 2026-07-02 09:00
          id: 2
          reply_to: 1
          text: b
        """)

      assert error =~ "circle"
    end

    test "the same field twice in one comment", %{tmp_dir: dir} do
      {[], [error]} =
        read(dir, "- author: kb\n  author: kb again\n  date: 2026-07-01 09:00\n  text: a\n")

      assert error =~ "author"
    end

    test "a line that is neither a comment nor a field", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  text: a\nstray\n")
      assert error =~ "line 4"
    end

    test "words longer than one comment holds", %{tmp_dir: dir} do
      long = String.duplicate("x", Texttile.Comments.body_limit() + 1)
      {[], [error]} = read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  text: #{long}\n")
      assert error =~ "longer"
    end

    test "a name longer than a name may be", %{tmp_dir: dir} do
      long = String.duplicate("x", 121)
      {[], [error]} = read(dir, "- author: #{long}\n  date: 2026-07-01 09:00\n  text: a\n")
      assert error =~ "author"
    end

    test "every complaint of one file arrives at once", %{tmp_dir: dir} do
      {[], errors} =
        read(dir, """
        - author: a
          text: no date
        - date: 2026-07-02 09:00
          text: no author
        """)

      assert length(errors) == 2
    end
  end

  describe "the text block" do
    test "keeps its own indentation past the four spaces", %{tmp_dir: dir} do
      {[comment], []} =
        read(dir, """
        - author: kb
          date: 2026-07-01 09:00
          text: |
            One line

              indented deeper
        """)

      assert comment.text == "One line\n\n  indented deeper"
    end

    test "a line of a text that looks like a field stays text", %{tmp_dir: dir} do
      {[comment], []} =
        read(dir, """
        - author: kb
          date: 2026-07-01 09:00
          text: |
            author: not a field
        """)

      assert comment.text == "author: not a field"
    end

    test "an empty text block is a missing text", %{tmp_dir: dir} do
      {[], [error]} = read(dir, "- author: kb\n  date: 2026-07-01 09:00\n  text: |\n")
      assert error =~ "text"
    end
  end
end
