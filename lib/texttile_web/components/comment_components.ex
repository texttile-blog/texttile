defmodule TexttileWeb.CommentComponents do
  @moduledoc """
  The comment row of the desk and the one rule it follows, in one
  wording. The Comments overview and the editor's Comments tab both
  draw from here, so the two screens can never drift apart.
  """

  use Phoenix.Component

  alias Texttile.Comments

  @doc """
  One comment on a desk screen: the name, the waiting mark while the
  reader has not confirmed, the moment it arrived, the words, and what
  the desk can do with it - Edit, Release while it waits, Delete.
  `article` set draws the "on <text>" jump of the overview. `editing`
  puts the words in a field instead, `error` says why the last save
  did not take.
  """
  attr :comment, :any, required: true
  attr :waiting, :boolean, required: true
  attr :article, :any, default: nil
  attr :editing, :boolean, default: false
  attr :error, :string, default: nil

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
          <span :if={Comments.released?(@comment)}>· let through</span>
          <span :if={Comments.edited?(@comment)}>· edited</span>
        </span>
      </div>

      <form
        :if={@editing}
        id={"edit-comment-#{@comment.id}"}
        phx-submit="save_comment"
        class="mt-[7px] max-w-[62ch]"
      >
        <input type="hidden" name="comment_id" value={@comment.id} />
        <%!-- the list behind this form reloads on every comment posted
             anywhere on the site; ignored, the field keeps what the
             desk has typed into it so far --%>
        <div id={"edit-body-#{@comment.id}"} phx-update="ignore">
          <textarea
            name="body"
            rows="4"
            maxlength={Comments.body_limit()}
            class="w-full font-serif text-[15.5px] leading-[1.55]"
            aria-label="The words of the comment"
            autofocus
          >{@comment.body}</textarea>
        </div>
        <p :if={@error} class="hint text-accent" id={"edit-error-#{@comment.id}"}>{@error}</p>
        <div class="mt-[9px] btn-row">
          <button class="btn sm solid">Save</button>
          <button type="button" class="btn sm" phx-click="cancel_edit">Cancel</button>
        </div>
      </form>

      <p :if={!@editing} class="mt-[5px] font-serif text-[15.5px] leading-[1.55] max-w-[62ch]">
        {@comment.body}
      </p>
      <%!-- three actions on every row would shout in a list this long,
           so they are quiet like the Restore of a version --%>
      <div :if={!@editing} class="mt-[7px] btn-row -ml-[10px]">
        <button class="btn quiet sm" phx-click="start_edit" phx-value-id={@comment.id}>Edit</button>
        <button
          :if={@waiting}
          class="btn quiet sm"
          phx-click="release_comment"
          phx-value-id={@comment.id}
        >
          Release
        </button>
        <button class="btn quiet sm" phx-click="delete_comment" phx-value-id={@comment.id}>
          Delete
        </button>
      </div>
    </div>
    """
  end

  @doc """
  One comment in the trash: what it said, where it stood, the day it
  goes for good, and the way back.
  """
  attr :comment, :any, required: true

  def trashed_item(assigns) do
    ~H"""
    <div class="py-[14px] border-b border-hair" id={"trash-#{@comment.id}"}>
      <div class="flex flex-wrap gap-[9px] items-baseline text-[13.5px] font-semibold">
        {@comment.name}
        <span class="font-normal text-faint text-[12.5px]">
          <span class="num">{Calendar.strftime(@comment.inserted_at, "%Y-%m-%d %H:%M")}</span>
          · on
          <.link navigate={"/admin/texts/#{@comment.article.id}?tab=comments"} class="link">
            {Texttile.Articles.display_title(@comment.article)}
          </.link>
          · goes for good on
          <span class="num">{Calendar.strftime(@comment.delete_after, "%Y-%m-%d")}</span>
        </span>
      </div>
      <p class="mt-[5px] font-serif text-[15.5px] leading-[1.55] max-w-[62ch] text-dim">
        {@comment.body}
      </p>
      <div class="mt-[7px] -ml-[10px]">
        <button class="btn quiet sm" phx-click="restore_comment" phx-value-id={@comment.id}>
          Restore
        </button>
      </div>
    </div>
    """
  end

  @doc """
  The one rule, in the one wording. Nothing here is an approval queue:
  nothing waits for the desk. The desk can make one exception at a
  time, and it can take its own back out of the trash.
  """
  def comment_rule(true = _require_confirmation?) do
    "Readers confirm their email first. A comment stays out of the text until " <>
      "the reader follows the link in the mail. Until then only you see it, " <>
      "marked \"not confirmed yet\", and Release puts that one comment under the " <>
      "text without waiting. Delete keeps a comment in the trash for #{Comments.trash_days()} " <>
      "days, silently, and then it is gone. Spam is filtered invisibly: honeypot, " <>
      "timing, rate limit. No captcha, ever."
  end

  def comment_rule(false) do
    "A comment appears under the text the moment a reader sends it, and nobody " <>
      "confirms anything. Delete keeps a comment in the trash for #{Comments.trash_days()} " <>
      "days, silently, and then it is gone. Spam is filtered invisibly: honeypot, " <>
      "timing, rate limit. No captcha, ever."
  end

  @doc """
  Why the last save did not take, in the words of the changeset that
  refused it: nothing there, or more than a comment holds.
  """
  def edit_error(%Ecto.Changeset{} = changeset) do
    case Keyword.get(changeset.errors, :body) do
      {_message, opts} ->
        if Keyword.get(opts, :validation) == :length do
          "A comment holds #{Keyword.get(opts, :count)} characters at most. Nothing was saved."
        else
          "A comment needs some words. Nothing was saved."
        end

      nil ->
        "Those words were not saved."
    end
  end
end
