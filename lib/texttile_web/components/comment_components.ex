defmodule TexttileWeb.CommentComponents do
  @moduledoc """
  The comment row of the desk and the one rule it follows, in one
  wording. The Comments overview and the editor's Comments tab both
  draw from here, so the two screens can never drift apart.
  """

  use Phoenix.Component

  @doc """
  One comment on a desk screen: the name, the waiting mark while the
  reader has not confirmed, the moment it arrived, the words, and
  Delete. `article` set draws the "on <text>" jump of the overview.
  """
  attr :comment, :any, required: true
  attr :waiting, :boolean, required: true
  attr :article, :any, default: nil

  def comment_item(assigns) do
    ~H"""
    <div class="py-[14px] border-b border-hair" id={"comment-#{@comment.id}"}>
      <div class="flex flex-wrap gap-[9px] items-baseline text-[13.5px] font-semibold">
        {@comment.name}
        <span :if={@waiting} class="wait">not confirmed yet</span>
        <span class="font-normal text-faint text-[12.5px]">
          <span class="num">{Calendar.strftime(@comment.inserted_at, "%Y-%m-%d %H:%M")}</span>
          <%= if @article do %>
            · on
            <.link navigate={"/admin/texts/#{@article.id}?tab=comments"} class="link">
              {Texttile.Articles.display_title(@article)}
            </.link>
          <% end %>
        </span>
      </div>
      <p class="mt-[5px] font-serif text-[15.5px] leading-[1.55] max-w-[62ch]">{@comment.body}</p>
      <div class="mt-[9px]">
        <button class="btn sm" phx-click="delete_comment" phx-value-id={@comment.id}>
          Delete
        </button>
      </div>
    </div>
    """
  end

  @doc """
  The one rule, in the one wording. Nothing here is an approval queue:
  no admin ever lets a comment through.
  """
  def comment_rule(true = _require_confirmation?) do
    "Readers confirm their email first. A comment stays out of the text until " <>
      "the reader follows the link in the mail. Until then only you see it, " <>
      "marked \"not confirmed yet\". Delete removes a comment silently. Spam is " <>
      "filtered invisibly: honeypot, timing, rate limit. No captcha, ever."
  end

  def comment_rule(false) do
    "A comment appears under the text the moment a reader sends it, and nobody " <>
      "confirms anything. Delete removes a comment silently. Spam is filtered " <>
      "invisibly: honeypot, timing, rate limit. No captcha, ever."
  end
end
