defmodule TexttileWeb.MailHTML do
  @moduledoc """
  The one HTML layout every mail of the blog wears: the site's name on
  top, a heading, a few lines, one button in the blog's own colour, and
  the small print. A notifier says what goes in; this module says how
  it looks. The plain-text part of each mail stays with its notifier.

  Mail programs ignore most of CSS and every stylesheet they did not
  get, so the styles stand inline, the layout is two tables, and the
  colours arrive as plain values. The one `<style>` carries what only a
  capable program reads: the dark mode and the full-width button on a
  phone. Nothing is loaded from outside: the picture, if any, travels
  inside the mail and is named by its content id.
  """

  use Phoenix.Component

  @font ~s(-apple-system, "Segoe UI", Helvetica, Arial, sans-serif)

  @doc """
  The HTML body of one mail. Required: `:site` (the title), `:colors`
  (`Texttile.Settings.button_colors/0`), `:subject`, `:heading` and
  `:button` (`{label, url}`). Optional, in the order they appear:
  `:picture` (the content id of an inline square), `:meta` (a quiet
  line under the heading), `:lines` (paragraphs), `:quote` (a text a
  person wrote), `:below` (lines under the button), `:link`
  (`{label, url}`, a second way on), `:small` (the fine print) and
  `:foot` (`{text, label, url}`, why the mail came and the way off).
  """
  def render(mail) do
    assigns =
      Map.merge(
        %{
          picture: nil,
          meta: nil,
          lines: [],
          quote: nil,
          below: [],
          link: nil,
          small: nil,
          foot: nil,
          home: TexttileWeb.Endpoint.url(),
          lang: Gettext.get_locale(TexttileWeb.Gettext),
          font: @font
        },
        Map.new(mail)
      )

    assigns
    |> layout()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp layout(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@lang}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <meta name="supported-color-schemes" content="light dark" />
        <title>{@subject}</title>
        <style>
          @media (prefers-color-scheme: dark) {
            .tt-page { background: #141414 !important; color: #ececec !important; }
            .tt-ink { color: #ececec !important; }
            .tt-mute { color: #a0a0a0 !important; }
            .tt-line { border-color: #383838 !important; }
          }
          @media (max-width: 520px) {
            .tt-button { display: block !important; text-align: center !important; }
          }
        </style>
      </head>
      <body class="tt-page" style="margin:0;padding:0;background:#ffffff;color:#1a1a1a;">
        <table
          role="presentation"
          class="tt-page"
          width="100%"
          cellpadding="0"
          cellspacing="0"
          border="0"
          style="background:#ffffff;"
        >
          <tr>
            <td align="center" style="padding:24px 20px 28px;">
              <table
                role="presentation"
                width="100%"
                cellpadding="0"
                cellspacing="0"
                border="0"
                style="max-width:480px;"
              >
                <tr>
                  <td
                    class="tt-ink"
                    style={"font-family:#{@font};font-size:16px;line-height:1.55;color:#1a1a1a;text-align:left;"}
                  >
                    <a
                      href={@home}
                      class="tt-ink"
                      style="display:block;margin:0 0 20px;font-size:14px;font-weight:700;color:#1a1a1a;text-decoration:none;"
                    >
                      {@site}
                    </a>
                    <img
                      :if={@picture}
                      src={"cid:" <> @picture}
                      width="480"
                      alt=""
                      style="display:block;width:100%;max-width:480px;height:auto;margin:0 0 18px;border:0;border-radius:3px;"
                    />
                    <h1
                      class="tt-ink"
                      style="margin:0 0 6px;font-size:23px;line-height:1.25;font-weight:700;color:#1a1a1a;"
                    >
                      {@heading}
                    </h1>
                    <p
                      :if={@meta}
                      class="tt-mute"
                      style="margin:0 0 14px;font-size:13px;color:#6b6b6b;"
                    >
                      {@meta}
                    </p>
                    <p :for={line <- @lines} style="margin:0 0 14px;">{line}</p>
                    <p
                      :if={@quote}
                      class="tt-line"
                      style="margin:0 0 18px;padding:2px 0 2px 14px;border-left:3px solid #e6e6e6;"
                    >
                      <%= for {part, i} <- Enum.with_index(String.split(@quote, ~r/\R/)) do %>
                        <br :if={i > 0} />{part}
                      <% end %>
                    </p>
                    <p style="margin:4px 0 14px;">
                      <a
                        href={elem(@button, 1)}
                        class="tt-button"
                        style={"display:inline-block;padding:11px 20px;border-radius:4px;background:#{@colors.solid};color:#{@colors.onsolid};font-size:15px;font-weight:600;text-decoration:none;"}
                      >
                        {elem(@button, 0)}
                      </a>
                    </p>
                    <p :for={line <- @below} style="margin:0 0 14px;font-size:15px;">{line}</p>
                    <p :if={@link} style="margin:0 0 14px;font-size:14px;">
                      <a href={elem(@link, 1)} class="tt-ink" style="color:#1a1a1a;">
                        {elem(@link, 0)}
                      </a>
                    </p>
                    <p
                      :if={@small}
                      class="tt-mute"
                      style="margin:0 0 14px;font-size:13px;color:#6b6b6b;"
                    >
                      {@small}
                    </p>
                    <p
                      :if={@foot}
                      class="tt-mute tt-line"
                      style="margin:22px 0 0;padding-top:12px;border-top:1px solid #e6e6e6;font-size:12px;color:#6b6b6b;"
                    >
                      {elem(@foot, 0)}
                      <a href={elem(@foot, 2)} class="tt-mute" style="color:#6b6b6b;">
                        {elem(@foot, 1)}
                      </a>
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end
end
