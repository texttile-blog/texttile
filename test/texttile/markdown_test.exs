defmodule Texttile.MarkdownTest do
  use ExUnit.Case, async: true

  alias Texttile.Markdown

  test "renders markdown" do
    html = Markdown.to_html("# Us\n\n**bold** and [a link](https://example.org)\n\n- one\n- two")

    assert html =~ "<h1>Us</h1>"
    assert html =~ "<strong>bold</strong>"
    assert html =~ ~s(<a href="https://example.org">a link</a>)
    assert html =~ "<li>one</li>"
  end

  test "raw HTML is shown as text, never executed" do
    html = Markdown.to_html("hello <script>alert(1)</script> <img src=x onerror=y>")

    refute html =~ "<script>"
    refute html =~ "<img"
    assert html =~ "&lt;script&gt;"
  end
end
