defmodule TexttileWeb.TextsLive do
  @moduledoc """
  The Texts overview, still empty: the desk shell exists, the grid
  comes with the first writing feature.
  """
  use TexttileWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Texts")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Texts"
      active="texts"
      others={@others}
    >
      <div class="max-w-[1060px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">Texts</h1>
          <span class="note num" id="gridCount">0 texts</span>
          <span class="sp"></span>
          <button class="btn solid" disabled title="Writing texts comes in the next step">
            New text
          </button>
        </div>
        <p class="note mt-[26px]" id="texts-empty">
          No texts yet. Writing them comes in the next step of the build.
        </p>
        <p class="hidden md:block text-[12.5px] text-faint mt-9 pt-[13px] border-t border-hair">
          The keys, once their sections are here:
          <b class="text-dim num">1</b>
          New text · <b class="text-dim num">2</b>
          Texts · <b class="text-dim num">3</b>
          Comments · <b class="text-dim num">7</b>
          Newsletter · <b class="text-dim num">8</b>
          Stats · <b class="text-dim num">9</b>
          Settings · <b class="text-dim num">0</b>
          View site · <b class="text-dim">/</b>
          search. The keys sleep while you are typing in a field.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
