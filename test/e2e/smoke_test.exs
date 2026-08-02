defmodule TexttileWeb.E2E.SmokeTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  @moduletag :e2e

  test "the home page renders in a real browser", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("p", text: "Peace of mind from prototype to production.")
  end
end
