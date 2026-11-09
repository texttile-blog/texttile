defmodule Texttile.Settings.ThemeTest do
  use ExUnit.Case, async: true

  alias Texttile.Settings.Theme

  describe "compact/1" do
    test "keeps only the theme's own tokens, and only where they leave the default" do
      css = """
      :root {
        --tt-accent: hotpink;
        --tt-paper: #ffffff;
        --fld-bg: transparent;
        --fld-r: 0px;
      }
      """

      assert Theme.compact(css) == ":root {\n  --tt-accent: hotpink;\n}\n"
    end

    test "the default, pasted back whole, stores nothing" do
      assert Theme.compact(Theme.default()) == ""
    end

    test "reads the last declaration of a token, and skips comments" do
      css = """
      /* --tt-ink: red; */
      :root { --tt-ink: #111111; }
      :root { --tt-ink: #222222; }
      """

      assert Theme.compact(css) == ":root {\n  --tt-ink: #222222;\n}\n"
    end

    test "a value cannot leave its declaration" do
      assert Theme.compact(":root { --tt-ink: red } body { color: blue; }") ==
               ":root {\n  --tt-ink: red;\n}\n"
    end
  end

  describe "ignored/1" do
    test "names every declaration that is not a theme token, once" do
      css = ":root { --fld-bg: transparent; --tt-wash1: #fff; --fld-bg: none; --tt-ink: #000; }"

      assert Theme.ignored(css) == ["--fld-bg", "--tt-wash1"]
    end
  end

  describe "merged/1" do
    test "is the default sheet with the stored values in their place" do
      merged = Theme.merged(":root {\n  --tt-accent: hotpink;\n}\n")

      assert merged =~ ~r/--tt-accent:\s+hotpink;/
      assert merged =~ "--tt-ink:"
      assert Theme.compact(merged) == ":root {\n  --tt-accent: hotpink;\n}\n"
    end

    test "is the default while nothing is stored" do
      assert Theme.merged("") == Theme.default()
    end
  end
end
