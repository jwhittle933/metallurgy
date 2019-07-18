defmodule Absinthe.JPG do
  alias __MODULE__
  alias Absinthe.JPG.Decoder
  use Bitwise, skip_operators: true

  @moduledoc """
  Reference: http://www.fileformat.info/format/jpeg/egff.htm
  Reference: https://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/JPEG.html
  Reference: https://www.impulseadventure.com/photo/jpeg-huffman-coding.html

  A port of the Golang image/jpeg package.

  JPG Header: <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0>>

  Base16: <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00>>
  Trailer: <<0xFF, 0xD9>>

  The actual JPEG data file follows all APP0 markers.

  To identify a JFIF file or data stream, scan for the values 0xFF 0xD8 0xFF. This will identify the SOI marker,
  followed by another marker. In a proper JFIF file, the next byte will be 0xE0, indicating a JFIF APP0 marker
  segment. It is possible that one or more other marker segments may be erroneously written between the SOI and
  JFIF APP0 markers. The next two bytes (the APP0 segment length) vary in value, but are typically 0x00 0x10,
  and these are followed by the five byte 0x4A 0x46 0x49 0x46 0x00. If these values are found, the SOI marker
  (0xFF 0xD8) marks the beginning of the JFIF data strean. If only 0xFF 0xD8 0xFF values are found, but not the
  remaining data, then a "raw" JPEG data stream has been found. All JPEG and JFIF data streams end with EOI
  (end of image) marker values 0xFF 0xD9.

  There are many proprietary image file formats which contain JPEG data. Scanning for the JPEG SOI and reading
  until the EOI marker will usually allow you to extract the JPEG/JFIF data stream.
  """

  @jpg_signature <<255::size(8), 216::size(8)>>

  defmodule ExceptionUnreadBytesError do
    @moduledoc """
    Error raised when fill() called with unread bytes
    """
    defexception [:message]
  end

  defmodule ExceptionMissingFF00 do
    @moduledoc """
    Error raised when missing <<0xFF, 0x00>>
    """
    defexception [:message]
  end

  @doc """
  SOI is is the start of the image, always FF D8

  APP0 is the application marker, always FF E0

  Length is the size of the JFIF (APP0) segment, including the length field itself and any thumbnail data contained
  in the APP0 segment. The value of Length = 16 + 3 * XThumbnail * YThumbnail

  Identifier contains the values 4A 46 49 46 00 (JFIF)

  Version id's the version of JFIF spec, with the first byte containing the major revision number, the second
  containing the minor revision number.

  Units, Xdensity, and Ydensity id the unit of measurement used to describe the image res. 0x01 for dots / inch,
  0x02 for dots / centimeter, 0x00 for none.

  Xdensity and Ydensity are the horizontal and vertical resolution of the image data. If Units is 0x00, the Xdensity
  and Ydensity fields will contain the pixes aspect ratio (Xdensity:Ydensity).

  XThumbnail and YThumbnail give the dimensions of the thumbnail image included in the JFIF APP0 marker. If no thumbnail
  image is included in the marker, these fields contain 0. The thumbnail data itself consists of an array of
  XThumbnail * YThumbnail pixel values, where each pixel occupies 3 bytes and contians 24-bit RGB value (stored in the order
  R, G, B). No compression is performed on the thumbnail.

  """
  @type t() :: %__MODULE__{
          length: iodata(),
          identifier: iodata(),
          version: iodata(),
          units: iodata(),
          xdensity: iodata(),
          ydensity: iodata(),
          xthumbnail: iodata(),
          ythumbnail: iodata(),
          content: iodata()
        }
  defstruct [
    :length,
    :identifier,
    :version,
    :units,
    :xdensity,
    :ydensity,
    :xthumbnail,
    :ythumbnail,
    :content
  ]

  def decode(
        <<0xFF, 0xD8, 0xFF, 0xE0, length::binary-size(2), id::binary-size(5),
          version::binary-size(2), units::binary-size(1), xdensity::binary-size(1),
          ydensity::binary-size(1), xthumb::binary-size(3), ythumb::binary-size(3), rest::binary>>
      ) do
    IO.puts("Found JFIF data stream")

    %JPG{
      length: length,
      identifier: id,
      version: version,
      units: units,
      xdensity: xdensity,
      ydensity: ydensity,
      xthumbnail: xthumb,
      ythumbnail: ythumb,
      content: rest
    }
  end

  def decode(<<_soi::binary-size(3), raw::binary>>) do
    %JPG{
      content: raw
    }
  end

  @doc """
  fill fills up the decoder.bytes.buf buffer from the underlying reader. It
  should only be called when there are no unread bytes in decoder.bytes
  """
  @spec fill(Decoder.t()) :: Decoder.t() | no_return()
  def fill(%Decoder{bytes: %Decoder.Bytes{i: i, j: j}}) when i != j do
    raise(ExceptionUnreadBytesError, message: "jpeg: fill called when uread bytes exist")
  end

  def fill(%Decoder{bytes: %{j: j}} = decoder) when j > 2 do
    val_index_0 = decoder.bytes.j - 2
    val_index_1 = decoder.bytes.j - 1

    {:ok, new_val_0} = decoder.bytes.buf |> binary_part(val_index_0, 1)
    {:ok, new_val_1} = decoder.bytes.buf |> binary_part(val_index_1, 1)

    new_bytes_list =
      decoder.bytes.buf
      |> :binary.bin_to_list()
      |> List.replace_at(val_index_0, new_val_0)
      |> List.replace_at(val_index_1, new_val_1)
      |> Enum.into(<<>>, fn byte -> <<byte::binary>> end)

    decoder = %Decoder{
      decoder
      | bytes: %Decoder.Bytes{decoder.bytes | buf: new_bytes_list, i: 2, j: 2}
    }

    fill(decoder)
  end

  def fill(decoder) do
    range = Range.new(decoder.bytes.j, Enum.count(decoder.bytes.buf) - 1)
    read_list = decoder.bytes.buf |> Enum.slice(range)

    # =======>>>>>>
    # implement byte Reader for decoder struct, read buffer bytes, append to decoder.bytes.j, and return decoder
    # ========>>>>>
  end

  @doc """
  read_byte_stuffed_byte is like read_byte but is for byte-stuffed Huffman data
  """
  @spec read_byte_stuffed_byte(Decoder.t()) :: {:ok, iodata(), Decoder.t()} | no_return
  def read_byte_stuffed_byte(%Decoder{bytes: %Decoder.Bytes{i: i, j: j}} = decoder)
      when i + 2 <= j do
    {:ok, x} = decoder.bytes.buf |> binary_part(i, 1)

    decoder = %Decoder{
      decoder
      | bytes: %Decoder.Bytes{decoder.bytes | i: decoder.bytes.i + 1, n_unreadable: 1}
    }

    with true <- x != <<0xFF>> do
      {:ok, x, decoder}
    else
      false ->
        with false <- {:ok, <<0x00>>} = decoder.bytes.buf |> binary_part(decoder.bytes.i, 1) do
          raise(ExceptionMissingFF00, message: "missing <<0xFF, 0x00>> byte sequence")
        else
          _ ->
            decoder = %Decoder{
              decoder
              | bytes: %Decoder.Bytes{decoder.bytes | i: decoder.bytes.i + 1, n_unreadable: 2}
            }

            {:ok, <<0xFF>>, decoder}
        end
    end
  end

  @spec read_byte_stuffed_byte(Decoder.t()) :: {:ok, iodata(), Decoder.t()} | no_return
  def read_byte_stuffed_byte(%Decoder{} = decoder) do
    {x, decoder} =
      %Decoder{decoder | bytes: %Decoder.Bytes{decoder.bytes | n_unreadable: 0}}
      |> read_byte

    decoder = %Decoder{decoder | bytes: %Decoder.Bytes{n_unreadable: 1}}

    with true <- x != <<0xFF>> do
      {:ok, x, decoder}
    else
      _ ->
        {x, decoder} = decoder |> read_byte
        decoder = %Decoder{decoder | bytes: %Decoder.Bytes{n_unreadable: 2}}

        unless x == <<0x00>>,
          do: raise(ExceptionMissingFF00, message: "missing <<0xFF, 0x00>> byte sequence")

        {:ok, <<0xFF>>, decoder}
    end
  end

  @doc """
  unread_byte_stuff_byte undoes the most recent read_byte_stuffed_byte call,
  giving a byte of data back from decoder.bits to decoder.bytes. The Huffman
  look-up table requires at least 8 bits for look-up, which means the Huffman
  decoding can sometimes overshoot and read one or two too many bytes. Two-byte
  overshoot can happen when expecting to read a 0xFF 0x00 byte-stuffed byte.
  """
  @spec unread_byte_stuffed_byte(Decoder.t()) :: Decoder.t() | {:error, String.t()}
  def unread_byte_stuffed_byte(%Decoder{} = decoder) do
    with true <- decoder.bits.n >= 8 do
      a_shift_right = bsr(decoder.bits.a, 8)
      new_n = decoder.bits.n - 8
      m_shift_right = bsr(decoder.bits.m, 8)

      %Decoder{
        decoder
        | bits: %Decoder.Bits{decoder.bits | a: a_shift_right, m: m_shift_right, n: new_n},
          bytes: %Decoder.Bytes{
            decoder.bytes
            | i: decoder.bytes.i - decoder.bytes.n_unreadable,
              n_unreadable: 0
          }
      }
    else
      _ ->
        %Decoder{
          decoder
          | bytes: %Decoder.Bytes{
              decoder.bytes
              | i: decoder.bytes.i - decoder.bytes.n_unreadable,
                n_unreadable: 0
            }
        }
    end
  end

  @doc """
  read_byte returns the next byte, whether buffered or not buffered. It does
  not care about byte stuffing.
  """
  @spec read_byte(Decoder.t()) :: {integer(), Decoder.t()} | no_return
  def read_byte(%Decoder{bytes: %Decoder.Bytes{i: i, j: j}} = decoder) when i == j do
    decoder
    |> fill
    |> read_byte
  end

  @spec read_byte(Decoder.t()) :: {integer(), Decoder.t()} | no_return
  def read_byte(%Decoder{bytes: %Decoder.Bytes{buf: buf, i: i}} = decoder) do
    {binary_part(buf, i, 1),
     %Decoder{decoder | bytes: %{decoder.bytes | i: decoder.bytes.i + 1, n_unreadable: 0}}}
  end

  @doc """
  read_full reads exactly length n of decoder.bytes.buf
  """
  @spec read_full(Decoder.t(), [iodata()]) :: Decoder.t() | no_return
  def read_full(
        %Decoder{bytes: %Decoder.Bytes{n_unreadable: n_unreadable}, bits: %Decoder.Bits{n: n}} =
          decoder,
        bin_list
      )
      when n_unreadable != 0 and n >= 8 do
    decoder
    |> unread_byte_stuffed_byte()
    |> read_full(bin_list)
  end

  def read_full(%Decoder{bytes: %Decoder.Bytes{n_unreadable: n}} = decoder, bin_list)
      when n != 0 do
    %Decoder{decoder | bytes: %Decoder.Bytes{decoder.bytes | n_unreadable: 0}}
    |> read_full(bin_list)
  end

  def read_full(%Decoder{bytes: %Decoder.Bytes{i: i, j: j}} = decoder, bin_list) do
    src = decoder.bytes.buf |> Enum.slice(Range.new(i, j))
    {decoder, _, _} = read_full_looper(decoder, bin_list, src)
    decoder
  end

  @doc """
  read_full_looper recursive helper func for read_full
  """
  defp read_full_looper(decoder, dst, src) do
    {dst, n} = copy(dst, src)
    dst = dst |> Enum.slice(Range.new(n, Enum.count(dst) - 1))
    decoder = %Decoder{decoder | bytes: %Decoder.Bytes{decoder.bytes | i: decoder.bytes.i + n}}

    with true <- dst == [] do
      {decoder, dst, src}
    else
      _ ->
        decoder
        |> fill
        |> read_full_looper(dst, src)
    end
  end

  @doc """
  ignore ignores the next n bytes
  """
  @spec ignore(Decoder.t(), integer()) :: Decoder.t() | no_return
  def ignore(
        %Decoder{bytes: %Decoder.Bytes{n_unreadable: n}, bits: %Decoder.Bits{n: n}} = decoder,
        n
      )
      when n_unreadable != 0 and n >= 8 do
    decoder
    |> unread_byte_stuffed_byte
    |> ignore(n)
  end

  def ignore(%Decoder{bytes: %Decoder.Bytes{n_unreadable: n}} = decoder, n) when n != 0 do
    %Decoder{decoder | bytes: %Decoder.Bytes{decoder.bytes | n_unreadable: 0}}
    |> ignore(n)
  end

  @doc """
  ignore_looper recursive helper for ignore
  """
  def ignore_looper(%Decoder{bytes: %Decoder.Bytes{j: j, i: i}} = decoder, n) do
    m =
      case j - i > n do
        true -> n
        false -> j - i
      end

    decoder = %Decoder{decoder | bytes: %Decoder.Bytes{decoder.bytes | i: decoder.bytes.i + m}}

    with true <- n == 0 do
      decoder
    else
      _ ->
        decoder
        |> fill
        |> ignore_looper(n)
    end
  end

  @doc """
  Reference: https://stackoverflow.com/questions/32642907/how-does-the-copy-function-work

  copy copies elements from a source slice into a destination slice.
  The source and destination may overlap. Copy returns the new list and the
  number of elements copied, which will be the minimum of length(src) and length(dst).
  """
  @spec copy(list(integer()), list(integer())) ::
          {list(integer() | none()), integer()} | {:atom, integer()}
  def copy([], _src), do: {:error, 0}
  def copy(dst, []), do: {dst, 0}

  def copy(dst, src) do
    # subtract 1 from each value for index use
    dst_l = Enum.count(dst) - 1
    src_l = Enum.count(src) - 1

    case dst_l >= src_l do
      true ->
        case dst_l > src_l do
          true ->
            {smaller_src_to_dst({src, src_l}, {dst, dst_l}), src_l + 1}

          false ->
            {src, src_l}
        end

      false ->
        {larger_src_to_dst({src, src_l}, {dst, dst_l}), dst_l + 1}
    end
  end

  defp smaller_src_to_dst({src, src_l}, {dst, dst_l}) do
    dst_tail = dst |> Enum.slice(Range.new(src_l, dst_l))
    src ++ dst_tail
  end

  defp larger_src_to_dst({src, src_l}, {dst, dst_l}) do
    src |> Enum.slice(Range.new(0, dst_l))
  end
end
