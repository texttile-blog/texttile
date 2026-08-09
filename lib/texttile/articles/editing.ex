defmodule Texttile.Articles.Editing do
  @moduledoc """
  What one open editor may do with the title and the body of an entry.

  `Texttile.Articles.Lock` owns the rule: one process per entry decides
  who writes. This is that rule read from one tab's own side, as one
  value with a name.

  It used to be three loose assigns in the editor, `holds_lock`,
  `holder` and `flush_pending`, moved by nine handlers, with
  `Lock.state/1` decoded by hand in four places and each decoding
  reading the reply a little differently. The subtlest rule in the
  editor sat in the middle of it: a free entry goes to whoever has it
  open, **except** to the tab that was just released for being idle,
  because taking it straight back would undo the release forever. That
  rule is `refresh/4` here, with a test of its own.

  Three states, and no fourth:

    * `:writing` - this tab holds the entry and may write it
    * `:flushing` - this tab still holds it and is handing over what is
      still in flight, so a takeover can go ahead
    * `:watching` - somebody else holds it, or this tab let it go; the
      title and the body are read-only, and `holder/1` says who has it
  """

  alias Texttile.Articles.Lock

  defstruct state: :watching, holder: nil

  @doc """
  Opens the entry in this tab: it writes when the entry is free, and
  watches when somebody else already has it.
  """
  def start(article_id, user_id, pid) do
    case Lock.acquire(article_id, user_id, pid) do
      :ok -> %__MODULE__{state: :writing}
      {:held, holder} -> %__MODULE__{state: :watching, holder: holder}
    end
  end

  @doc """
  Who holds the entry, from this tab's side: `:free`, `:mine`, or
  `{:held, holder}`. The one reading of `Lock.state/1`.
  """
  def who_holds(article_id, pid) do
    case Lock.state(article_id) do
      :free -> :free
      %{pid: ^pid} -> :mine
      holder -> {:held, holder}
    end
  end

  @doc """
  What this tab may do now, after the lock said something changed.

  Takes the state this tab was in, because that is what tells a tab
  that let the entry go from a tab that never had it.
  """
  def refresh(%__MODULE__{} = was, article_id, user_id, pid) do
    case who_holds(article_id, pid) do
      :mine ->
        %__MODULE__{state: :writing}

      {:held, holder} ->
        %__MODULE__{state: :watching, holder: holder}

      :free ->
        # A free entry goes to whoever has it open, except to the tab
        # that was just released for being idle: taking it straight
        # back would undo the release, forever. That tab turns
        # read-only and gets the entry again the moment its person
        # actually touches the text.
        if holds?(was) do
          %__MODULE__{state: :watching}
        else
          start(article_id, user_id, pid)
        end
    end
  end

  @doc """
  The lock asked this tab to hand over what is still in flight. A tab
  that does not hold the entry has nothing to hand over.
  """
  def flushing(%__MODULE__{} = editing) do
    if holds?(editing), do: %{editing | state: :flushing}, else: editing
  end

  @doc "The handover is through; this tab writes again."
  def flushed(%__MODULE__{state: :flushing} = editing), do: %{editing | state: :writing}
  def flushed(%__MODULE__{} = editing), do: editing

  @doc "Whether this tab may write the title and the body."
  def holds?(%__MODULE__{state: state}), do: state in [:writing, :flushing]

  @doc """
  `holds?/1` for a function head, so a handler that needs the entry can
  say so where it says what it answers.
  """
  defguard holding(editing) when editing.state in [:writing, :flushing]

  @doc "Whether this tab is writing, with nothing in flight."
  def writing?(%__MODULE__{state: state}), do: state == :writing

  @doc "Whether this tab is handing over what is still in flight."
  def flushing?(%__MODULE__{state: state}), do: state == :flushing

  @doc "Whether the title and the body are read-only in this tab."
  def read_only?(%__MODULE__{} = editing), do: not holds?(editing)

  @doc "Who has the entry, while somebody else does. Nil otherwise."
  def holder(%__MODULE__{holder: holder}), do: holder
end
