defmodule TexttileWeb.StatsComponents do
  @moduledoc """
  The blocks the numbers are drawn with: a bar per day, a row per
  source, and the way a count is written.

  The Stats screen shows them for the whole blog and the editor for
  one entry, so they live here and not in either of them. The design
  comes from the round-14 prototype.
  """

  use Phoenix.Component
  use Gettext, backend: TexttileWeb.Gettext

  @doc """
  One bar per step of the series, oldest left, with the two dates that
  bound it under the row. The busiest bar carries the accent, so the
  shape of the month reads without reading a number.

  `step` says what a bar is (`Texttile.Stats.step/1`): a series in
  months carries the year on its axis. With `pick`, every bar is a
  button that sends that event with the bar's first day, and the bar
  that is `open` is drawn in ink. Without it the bars are only drawn.

  A window nobody read holds no chart. Thirty flat stubs under an
  empty box say less than one line does, and they read as a fault.
  """
  attr :id, :string, required: true
  attr :series, :list, required: true
  attr :step, :atom, default: :day
  attr :pick, :string, default: nil
  attr :open, :map, default: nil

  def day_chart(assigns) do
    assigns = assign(assigns, :max, Enum.max(Enum.map(assigns.series, & &1.views), fn -> 0 end))

    ~H"""
    <p :if={@max == 0} class="note" id={"#{@id}Empty"}>
      {gettext(
        "Nothing counted in these days yet. The first reader who opens a page draws the first bar."
      )}
    </p>
    <div :if={@max > 0}>
      <div id={@id} class="flex items-end gap-[3px] h-[132px] pt-[18px] pb-[6px]">
        <%= for bar <- @series do %>
          <button
            :if={@pick}
            type="button"
            id={"bar-#{bar.from}"}
            class={[
              "flex-1 self-stretch flex items-end cursor-pointer rounded-t-[2px]",
              @open && @open.from == bar.from && "on"
            ]}
            title={bar_title(bar)}
            phx-click={@pick}
            phx-value-day={bar.from}
          >
            <i
              class={[
                "block w-full min-h-[2px] rounded-t-[2px]",
                bar_colour(bar.views, @max),
                @open && @open.from == bar.from && "!bg-ink"
              ]}
              style={"height:#{height(bar.views, @max)}%"}
            >
            </i>
          </button>
          <i
            :if={is_nil(@pick)}
            class={["flex-1 min-h-[2px] rounded-t-[2px]", bar_colour(bar.views, @max)]}
            style={"height:#{height(bar.views, @max)}%"}
            title={bar_title(bar)}
          >
          </i>
        <% end %>
      </div>
      <div class="flex justify-between text-[12px] text-faint pb-2 border-b border-hair">
        <span>{axis_label(List.first(@series).from, @step)}</span>
        <span>{axis_label(List.last(@series).to, @step)}</span>
      </div>
    </div>
    """
  end

  # A series in months reaches over a year or more, so its ends carry
  # the year.
  defp axis_label(day, :month), do: Texttile.I18n.format_month(day)
  defp axis_label(day, _step), do: day_label(day)

  defp bar_title(bar) do
    gettext("%{day}: %{views}",
      day: span_label(bar),
      views: ngettext("1 view", "%{count} views", bar.views)
    )
  end

  @doc """
  A span the way a person names it: one day as "18 Aug", a whole month
  as "Aug 2026", anything else as its two ends.
  """
  def span_label(%{from: from, to: to}) do
    cond do
      from == to ->
        day_label(from)

      from == Date.beginning_of_month(from) and to == Date.end_of_month(from) ->
        Texttile.I18n.format_month(from)

      true ->
        gettext("%{from} to %{to}", from: day_label(from), to: day_label(to))
    end
  end

  @doc """
  Where the readers came from, each source with the share it carries.
  A reader who arrived on no link is direct: a bookmark, a typed
  address, a mail program.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  def referrer_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table id={@id}>
        <thead>
          <tr>
            <th>{gettext("Source")}</th>
            <th class="w-[45%]">{gettext("Share")}</th>
            <th class="text-right num">%</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td>{row.host || gettext("direct")}</td>
            <td><span class="track"><i style={"width:#{row.share}%"}></i></span></td>
            <td class="text-right num">{row.share}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  A count as a person reads it: a thin space between the thousands, so
  2 310 is one number and no comma can be read as a decimal point.
  """
  def number(count) do
    count
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1\u2009")
    |> String.reverse()
  end

  @doc "A day as the charts write it: 30 Jun."
  defdelegate day_label(day), to: Texttile.I18n, as: :format_short_day

  defp bar_colour(views, max) when views == max and views > 0, do: "bg-accent"
  defp bar_colour(_views, _max), do: "bg-accentsoft"

  defp height(_views, 0), do: 0
  defp height(views, max), do: max(round(views / max * 100), 1)
end
