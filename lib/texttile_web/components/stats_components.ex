defmodule TexttileWeb.StatsComponents do
  @moduledoc """
  The blocks the numbers are drawn with: a bar per day, a row per
  source, and the way a count is written.

  The Stats screen shows them for the whole blog and the editor for
  one entry, so they live here and not in either of them. The design
  comes from the round-14 prototype.
  """

  use Phoenix.Component

  @doc """
  One bar per day of the window, oldest left, with the two dates that
  bound it under the row. The busiest bar carries the accent, so the
  shape of the month reads without reading a number.
  """
  attr :id, :string, required: true
  attr :days, :list, required: true

  def day_chart(assigns) do
    assigns = assign(assigns, :max, Enum.max(Enum.map(assigns.days, & &1.views), fn -> 0 end))

    ~H"""
    <div id={@id} class="flex items-end gap-[3px] h-[132px] pt-[18px] pb-[6px]">
      <i
        :for={day <- @days}
        class={["flex-1 min-h-[2px] rounded-t-[2px]", bar_colour(day.views, @max)]}
        style={"height:#{height(day.views, @max)}%"}
        title={"#{day_label(day.day)}: #{day.views} #{views_word(day.views)}"}
      >
      </i>
    </div>
    <div class="flex justify-between text-[12px] text-faint pb-2 border-b border-hair">
      <span>{day_label(List.first(@days).day)}</span>
      <span>{day_label(List.last(@days).day)}</span>
    </div>
    """
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
            <th>Source</th>
            <th class="w-[45%]">Share</th>
            <th class="text-right num">%</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td>{row.host || "direct"}</td>
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
  def day_label(day), do: "#{day.day} #{Calendar.strftime(day, "%b")}"

  defp bar_colour(views, max) when views == max and views > 0, do: "bg-accent"
  defp bar_colour(_views, _max), do: "bg-accentsoft"

  defp height(_views, 0), do: 0
  defp height(views, max), do: max(round(views / max * 100), 1)

  defp views_word(1), do: "view"
  defp views_word(_count), do: "views"
end
