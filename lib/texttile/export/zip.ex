defmodule Texttile.Export.Zip do
  @moduledoc """
  Writes a zip as a stream, piece by piece, so the first bytes leave
  before the last file has been read.

  Every file is stored, not compressed: a bundle is mostly pictures and
  films, which are compressed already, and deflating a large film costs
  minutes of CPU to save nothing. Nothing is written to disk on the way.

  An entry is `{name, content}`, where the content is a binary or an
  open file as `{io, size}`. The stream reads each open file twice:
  once for its checksum, which the header in front of it needs, and
  once to send it. It closes every file it was given, also when it is
  halted early.

  The zip has no zip64 records, so it holds at most 4 GiB. `size/1`
  says how large it will be before any byte has gone out.
  """

  import Bitwise

  # The largest offset and size a zip without zip64 can say.
  @max 0xFFFFFFFF
  @read 1024 * 1024

  # Bit 11 says the names are UTF-8.
  @flags 0x0800
  # Version 2.0 is what a stored file needs. The central record says the
  # zip was made on Unix, so the external attributes carry a file mode.
  @needed 20
  @made_by 0x0314
  @mode 0o100644

  @doc "The exact size of the zip, in bytes."
  def size(entries) do
    Enum.reduce(entries, 22, fn {name, content}, sum ->
      sum + 30 + 46 + 2 * byte_size(name) + content_size(content)
    end)
  end

  @doc "Whether the zip stays within what a zip without zip64 can hold."
  def fits?(entries), do: size(entries) <= @max and length(entries) <= 0xFFFF

  @doc "Closes the open files of `entries`, for a zip that is never sent."
  def close(entries), do: Enum.each(entries, &close_entry/1)

  @doc "The zip of `entries` as a stream of binaries."
  def stream(entries) do
    {date, time} = dos_now()

    Stream.transform(
      entries,
      fn -> {0, []} end,
      fn {name, content}, {offset, central} ->
        crc = checksum(content)
        size = content_size(content)

        header =
          <<0x04034B50::little-32, @needed::little-16, @flags::little-16, 0::little-16,
            time::little-16, date::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name)::little-16, 0::little-16, name::binary>>

        record =
          <<0x02014B50::little-32, @made_by::little-16, @needed::little-16, @flags::little-16,
            0::little-16, time::little-16, date::little-16, crc::little-32, size::little-32,
            size::little-32, byte_size(name)::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-16, @mode <<< 16::little-32, offset::little-32, name::binary>>

        {Stream.concat([header], pieces(content)),
         {offset + byte_size(header) + size, [record | central]}}
      end,
      fn {offset, central} = acc ->
        records = central |> Enum.reverse() |> IO.iodata_to_binary()
        count = length(central)

        finish =
          <<0x06054B50::little-32, 0::little-16, 0::little-16, count::little-16, count::little-16,
            byte_size(records)::little-32, offset::little-32, 0::little-16>>

        {[records <> finish], acc}
      end,
      fn _acc -> close(entries) end
    )
  end

  defp content_size({_io, size}), do: size
  defp content_size(data) when is_binary(data), do: byte_size(data)

  defp checksum(data) when is_binary(data), do: :erlang.crc32(data)

  defp checksum({io, _size}) do
    {:ok, 0} = :file.position(io, :bof)
    crc = io |> chunks() |> Enum.reduce(0, &:erlang.crc32(&2, &1))
    {:ok, 0} = :file.position(io, :bof)
    crc
  end

  defp pieces(data) when is_binary(data), do: [data]
  defp pieces({io, _size}), do: chunks(io)

  defp chunks(io) do
    Stream.unfold(io, fn io ->
      case :file.read(io, @read) do
        {:ok, data} -> {data, io}
        :eof -> nil
      end
    end)
  end

  defp close_entry({_name, {io, _size}}), do: File.close(io)
  defp close_entry({_name, _data}), do: :ok

  # A zip keeps the local time of its files to two seconds, in the form
  # MS-DOS gave it.
  defp dos_now do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    date = (max(year, 1980) - 1980) <<< 9 ||| month <<< 5 ||| day
    time = hour <<< 11 ||| minute <<< 5 ||| div(second, 2)
    {date, time}
  end
end
