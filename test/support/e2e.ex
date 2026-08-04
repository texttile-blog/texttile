defmodule TexttileWeb.E2E do
  @moduledoc """
  Shared plumbing for the browser tests.
  """

  @doc """
  Closes the test's browser context the moment the test ends, before
  the next one starts.

  The Playwright case closes contexts in a spawned process, so a page
  can outlive its test. Its LiveViews then reconnect mid-run under a
  sandbox owner that is already dead, and SQLite's single writer turns
  that race into stalls in whatever test runs next. Registered after
  the case's own setup, this runs first on exit and closes the context
  synchronously.
  """
  def close_browser_context_afterwards(%{conn: conn}) do
    ExUnit.Callbacks.on_exit(fn ->
      try do
        PlaywrightEx.BrowserContext.close(conn.context_id, timeout: 5_000)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end
end
