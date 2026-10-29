defmodule Refract.JSONL do
  @moduledoc """
  json lines reader and writer for refract (`.jsonl`, `.ndjson`), one value per line, streamed.
  lines of objects: keys become the header in first seen order, read from every line first so a
  key first seen late is kept; `scan: n` reads keys from the first n records only and a later new
  key raises; `columns:` gives the header outright. lines of arrays are lines of cells.
  records flatten and cells come back as in `Refract.JSON`; blank lines are skipped.
  `unnest:` and `keep:` read a child array of every line as in `Refract.JSON`.
  writes an object per line, values as `Refract.JSON` writes them.

      {:ok, rows} = Refract.JSONL.stream("events.jsonl")
      {:ok, result} = Refract.JSONL.classify("events.jsonl", shapes, scan: 1_000)
      {:ok, paths} = Refract.JSONL.write_chunks(rows, "out/events.jsonl", rows_per_file: 100_000)
  """

  use Refract.Reader
  use Refract.Writer

  alias Refract.Errors.ParseError
  alias Refract.JSON.Decode
  alias Refract.JSON.Objects
  alias Refract.JSON.Records

  @type open_opt ::
          {:scan, pos_integer() | nil}
          | {:columns, [String.t()] | nil}
          | {:unnest, [String.t()] | nil}
          | {:keep, %{String.t() => String.t()}}

  @type encode_opt :: {:header, [String.t()] | nil}

  @spec extension() :: String.t()

  @impl Refract.Writer
  def extension, do: "jsonl"

  @spec extensions() :: [String.t()]

  @impl Refract.Reader
  def extensions, do: ["jsonl", "ndjson"]

  @spec indexing() :: :records

  @impl Refract.Reader
  def indexing, do: :records

  @spec open(Refract.source(), [open_opt()]) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl Refract.Reader
  def open(source, opts) do
    opts = Keyword.validate!(opts, scan: nil, columns: nil, unnest: nil, keep: %{})
    scan = Keyword.fetch!(opts, :scan)
    columns = Keyword.fetch!(opts, :columns)
    unnest = Keyword.fetch!(opts, :unnest)
    keep = Keyword.fetch!(opts, :keep)

    validate_scan(scan)
    validate_columns(columns)
    Records.validate_unnest(unnest, keep)

    unnest = Records.unnest(unnest, keep)

    with {:ok, chunks} <- chunks(source) do
      elements = elements(chunks)

      eager(fn ->
        with {:ok, kind} <- elements |> Enum.take(1) |> kind() do
          {:ok, kind |> read_as(unnest) |> lines(elements, scan, columns, unnest)}
        end
      end)
    end
  end

  @spec facts(Refract.source(), [open_opt()]) :: {:ok, map()} | {:error, term()}

  @impl Refract.Reader
  def facts(source, opts) do
    opts = Keyword.validate!(opts, scan: nil, columns: nil, unnest: nil, keep: %{})
    scan = Keyword.fetch!(opts, :scan)
    columns = Keyword.fetch!(opts, :columns)
    unnest = Keyword.fetch!(opts, :unnest)
    keep = Keyword.fetch!(opts, :keep)

    validate_scan(scan)
    validate_columns(columns)
    Records.validate_unnest(unnest, keep)

    with {:ok, chunks} <- chunks(source) do
      eager(fn ->
        with {:ok, kind} <- chunks |> elements() |> Enum.take(1) |> kind() do
          {:ok, %{layout: layout(kind), unnest: unnest}}
        end
      end)
    end
  end

  @spec encode(Enumerable.t(), [encode_opt()]) :: Enumerable.t()

  @impl Refract.Writer
  def encode(rows, opts) do
    opts = Keyword.validate!(opts, header: nil)
    header = Keyword.fetch!(opts, :header)

    Objects.validate_header(header)

    rows
    |> Objects.encode(header)
    |> Stream.map(&[&1, "\n"])
  end

  defp validate_scan(nil), do: :ok
  defp validate_scan(scan) when is_integer(scan) and scan > 0, do: :ok

  defp validate_scan(scan) do
    raise ArgumentError, "scan must be a positive integer, got: #{inspect(scan)}"
  end

  defp validate_columns(nil), do: :ok
  defp validate_columns(columns), do: validate_columns(columns, columns)

  defp validate_columns([], _columns), do: :ok

  defp validate_columns([column | rest], columns) when is_binary(column),
    do: validate_columns(rest, columns)

  defp validate_columns(_rest, columns) do
    raise ArgumentError, "columns must be a list of names, got: #{inspect(columns)}"
  end

  defp chunks({:string, jsonl}), do: {:ok, [jsonl]}
  defp chunks({:stream, chunks}), do: {:ok, chunks}

  defp chunks(path) when is_binary(path) do
    with {:ok, file} <- File.open(path),
         :ok <- File.close(file) do
      {:ok, File.stream!(path, 65_536)}
    end
  end

  defp chunks(source), do: {:error, {:unsupported_source, source}}

  defp elements(chunks) do
    chunks
    |> split_lines()
    |> Stream.with_index(1)
    |> Stream.reject(fn {line, _number} -> String.trim(line) == "" end)
    |> Stream.map(fn {line, number} -> {line |> Decode.decode() |> at_line!(number), number} end)
  end

  defp split_lines(chunks),
    do: Stream.transform(chunks, fn -> "" end, &split_chunk/2, &last_line/1, fn _rest -> :ok end)

  defp split_chunk(chunk, rest) do
    [rest | lines] = (rest <> chunk) |> :binary.split("\n", [:global]) |> Enum.reverse()

    {Enum.reverse(lines), rest}
  end

  defp last_line(""), do: {[], ""}
  defp last_line(rest), do: {[rest], ""}

  defp kind([]), do: {:ok, :empty}
  defp kind([{element, number}]), do: element |> Records.start() |> at_line(number)

  defp layout(:empty), do: :empty
  defp layout(:object), do: :objects
  defp layout(:array), do: :arrays

  defp read_as(:empty, _unnest), do: :empty
  defp read_as(kind, nil), do: kind
  defp read_as(_kind, _unnest), do: :object

  defp lines(:empty, _elements, _scan, _columns, _unnest), do: []

  defp lines(:array, elements, _scan, _columns, _unnest),
    do: Stream.map(elements, &array_line/1)

  defp lines(:object, elements, scan, columns, unnest),
    do: elements |> header(scan, columns, unnest) |> object_lines(elements, unnest)

  defp header(elements, nil, nil, unnest),
    do: elements |> Stream.flat_map(&rows!(&1, unnest)) |> Records.header()

  defp header(elements, scan, nil, unnest),
    do: elements |> Stream.take(scan) |> Stream.flat_map(&rows!(&1, unnest)) |> Records.header()

  defp header(_elements, _scan, columns, _unnest), do: columns

  defp object_lines([], _elements, _unnest), do: []

  defp object_lines(header, elements, unnest) do
    known = MapSet.new(header)

    Stream.concat([header], Stream.flat_map(elements, &record_lines(&1, header, known, unnest)))
  end

  defp record_lines({_element, number} = element, header, known, unnest) do
    element
    |> rows!(unnest)
    |> Enum.map(&record_line(&1, number, header, known))
  end

  defp record_line(pairs, number, header, known) do
    pairs
    |> Enum.reject(fn {key, _cell} -> MapSet.member?(known, key) end)
    |> known_keys!(number)

    Records.line(pairs, header)
  end

  defp known_keys!([], _number), do: :ok

  defp known_keys!([{key, _cell} | _pairs], number) do
    raise ParseError, "line #{number} has the key #{inspect(key)}, which is not in the header"
  end

  defp rows!({element, number}, unnest) do
    element |> Records.expect(:object) |> at_line!(number)
    element |> Records.rows(unnest) |> at_line!(number)
  end

  defp array_line({element, number}) do
    element |> Records.expect(:array) |> at_line!(number)

    Records.cells(element)
  end

  defp at_line({:ok, value}, _number), do: {:ok, value}
  defp at_line({:error, detail}, number), do: {:error, {:parse_error, "line #{number} #{detail}"}}

  defp at_line!(:ok, _number), do: :ok
  defp at_line!({:ok, value}, _number), do: value

  defp at_line!({:error, {:parse_error, message}}, number) do
    raise ParseError, "line #{number}: #{message}"
  end

  defp at_line!({:error, detail}, number) do
    raise ParseError, "line #{number} #{detail}"
  end

  defp eager(read) do
    read.()
  rescue
    error in ParseError -> {:error, {:parse_error, Exception.message(error)}}
  end
end
