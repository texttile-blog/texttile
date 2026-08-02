defmodule TexttileWeb.E2E.SmokeTest do
  use PhoenixTest.Playwright.Case, async: true

  @moduletag :e2e

  test "the home page renders in a real browser", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("p", text: "Peace of mind from prototype to production.")
  end
end
