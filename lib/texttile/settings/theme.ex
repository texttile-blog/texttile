defmodule Texttile.Settings.Theme do
  @moduledoc """
  The theme contract: which custom properties a stored theme may set.

  The tokens are the declarations of the default theme,
  `assets/css/theme.css`: colours, corners and `color-scheme`. Everything
  else that shapes a screen (how a field is drawn, the writing surface)
  belongs to the app and follows its updates. A stored theme keeps only
  the tokens it changes, so a colour nobody touched follows the default
  too. See docs/decisions/031.

  Renaming or removing a token drops that value from every stored theme
  that set it, so say so in the release.
  """

  # The default theme. Embedded at compile time; the file in assets/
  # stays the single source, and app.css bundles the same file.
  @default_path Path.expand("../../../assets/css/theme.css", __DIR__)
  @external_resource @default_path
  @default File.read!(@default_path)

  @comment ~r{/\*.*?\*/}s
  @block ~r/\{([^{}]*)\}/
  @declaration ~r/\A\s*([-a-zA-Z0-9]+)\s*:\s*(.+?)\s*\z/s

  @doc "The default theme sheet, comments and all."
  def default, do: @default

  @doc """
  What to store for a theme as written: one `:root` rule with the tokens
  whose value leaves the default, in the default's order, or `""` when
  nothing does. Anything that is not a token is dropped.
  """
  def compact(css) do
    case overrides(css) do
      [] ->
        ""

      pairs ->
        ":root {\n" <> Enum.map_join(pairs, &"  #{elem(&1, 0)}: #{elem(&1, 1)};\n") <> "}\n"
    end
  end

  @doc "The declared names that are not tokens, each once, in order."
  def ignored(css) do
    tokens = defaults()

    css
    |> declarations()
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&Map.has_key?(tokens, &1))
    |> Enum.uniq()
  end

  @doc """
  The default sheet with a stored theme's values in their place: the
  whole list of tokens to edit, with every untouched one at today's
  default.
  """
  def merged(stored) do
    Enum.reduce(overrides(stored), @default, fn {name, value}, sheet ->
      pattern = ~r/^(\s*#{Regex.escape(name)}\s*:\s*)[^;]*;/m
      Regex.replace(pattern, sheet, fn _, before -> before <> value <> ";" end, global: false)
    end)
  end

  # The tokens in the default's order, each with the last value the
  # sheet gives it, kept where that value differs from the default.
  defp overrides(css) do
    given = Map.new(declarations(css))

    Enum.flat_map(declarations(@default), fn {name, default} ->
      case given[name] do
        nil -> []
        ^default -> []
        value -> [{name, value}]
      end
    end)
  end

  defp defaults, do: Map.new(declarations(@default))

  # Every declaration inside a rule, comments left out. A value never
  # holds a brace or a semicolon, so it cannot end its rule early.
  defp declarations(css) do
    css
    |> String.replace(@comment, "")
    |> then(&Regex.scan(@block, &1, capture: :all_but_first))
    |> Enum.flat_map(fn [body] -> String.split(body, ";") end)
    |> Enum.flat_map(fn line ->
      case Regex.run(@declaration, line) do
        [_, name, value] -> [{name, String.replace(value, ~r/\s+/, " ")}]
        nil -> []
      end
    end)
  end
end
