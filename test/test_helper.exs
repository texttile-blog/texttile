{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, TexttileWeb.Endpoint.url())

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Texttile.Repo, :manual)
